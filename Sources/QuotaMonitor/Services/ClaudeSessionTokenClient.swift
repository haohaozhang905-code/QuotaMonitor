import Foundation

/// 从本地 Claude Code 会话转录解析按天 token 用量。
///
/// 数据来源：`~/.claude/projects/**/*.jsonl`，逐行 JSON，assistant 消息的
/// `message.usage` 含 input/cache_creation/cache_read/output 各 token 数，
/// `message.model` 记录实际模型（用户切换 cc-switch 后会出现 deepseek-v4-flash）。
///
/// 统一口径：`input` = input_tokens + cache_read + cache_creation（Claude 的
/// input_tokens 不含缓存），cachedInput 单独列示，total = input + output。
///
/// 用 actor 持有 mtime 增量缓存，避免每次刷新全量重扫历史转录。
actor ClaudeSessionTokenClient {
    private struct FileCache: Codable, Equatable {
        let mtime: Date
        let fileSize: Int
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
        let processedByteCount: Int?

        func matches(mtime candidateMtime: Date, fileSize candidateSize: Int) -> Bool {
            fileSize == candidateSize
                && abs(mtime.timeIntervalSinceReferenceDate - candidateMtime.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    private struct PersistedCache: Codable {
        let version: Int
        let rootPath: String
        let entries: [String: FileCache]
    }

    private var cache: [URL: FileCache] = [:]
    private var didLoadPersistentCache = false
    private let root: URL
    private let persistentCacheURL: URL?

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        self.persistentCacheURL = root == nil ? Self.defaultPersistentCacheURL() : nil
    }

    func fetch() -> [DailyTokenUsage] {
        (try? fetchSnapshot().history) ?? []
    }

    /// 只统计模型名包含 deepseek 的消息（与 Codex 客户端口径一致）。
    func fetch(modelFilter: String?) -> [DailyTokenUsage] {
        guard modelFilter?.lowercased().contains("deepseek") == true else { return fetch() }
        return (try? fetchSnapshot().deepSeekHistory) ?? []
    }

    func fetchBuckets() -> [TokenUsageBucket] {
        (try? fetchSnapshot().buckets) ?? []
    }

    func fetchSnapshot() throws -> TokenSourceSnapshot {
        TokenSourceSnapshot(buckets: try scanBuckets())
    }

    private func scanBuckets() throws -> [TokenUsageBucket] {
        loadPersistentCacheIfNeeded()
        var newCache: [URL: FileCache] = [:]
        var buckets: [TokenUsageBucket] = []
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            if !FileManager.default.fileExists(atPath: root.path) { return [] }
            throw TokenSourceReadError.unreadableRoot(root)
        }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = values.contentModificationDate,
                  let fileSize = values.fileSize else {
                if let cached = cache[url] {
                    newCache[url] = cached
                    buckets.append(contentsOf: Self.makeBuckets(from: cached.modelByDay))
                }
                continue
            }
            let modelByDay: [String: TokenTotals]
            let cached = cache[url]
            if let cached, cached.matches(mtime: mtime, fileSize: fileSize) {
                newCache[url] = cached
                modelByDay = cached.modelByDay
            } else {
                let canContinue = cached?.processedByteCount == cached?.fileSize
                    && fileSize > (cached?.fileSize ?? 0)
                    && JSONLReader.isLineBoundary(at: cached?.fileSize ?? 0, in: url)
                let startingAt = canContinue ? UInt64(cached?.fileSize ?? 0) : 0
                let seed = canContinue ? cached : nil
                guard let parsed = parseFile(
                    url,
                    fallbackDay: Self.dayKey(for: mtime),
                    startingAt: startingAt,
                    seed: seed
                ) else {
                    guard let cached = cache[url] else { continue }
                    newCache[url] = cached
                    modelByDay = cached.modelByDay
                    for bucket in Self.makeBuckets(from: modelByDay) { buckets.append(bucket) }
                    continue
                }
                if parsed.modelByDay.isEmpty, let cached {
                    newCache[url] = cached
                    modelByDay = cached.modelByDay
                    for bucket in Self.makeBuckets(from: modelByDay) { buckets.append(bucket) }
                    continue
                }
                let entry = FileCache(
                    mtime: mtime,
                    fileSize: fileSize,
                    totalsByDay: parsed.totalsByDay,
                    deepSeekByDay: parsed.deepSeekByDay,
                    modelByDay: parsed.modelByDay,
                    processedByteCount: fileSize
                )
                newCache[url] = entry
                modelByDay = entry.modelByDay
            }
            buckets.append(contentsOf: Self.makeBuckets(from: modelByDay))
        }
        if enumerationError != nil { throw TokenSourceReadError.unreadableRoot(root) }
        let cacheChanged = cache != newCache
        cache = newCache
        if cacheChanged { savePersistentCache() }
        return TokenUsageBucket.combining(buckets)
    }

    private static func makeBuckets(from modelByDay: [String: TokenTotals]) -> [TokenUsageBucket] {
        modelByDay.compactMap { key, totals in
            let parts = key.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let model = TokenModelName.canonical(parts[1])
            return TokenUsageBucket(
                bucketStart: day(from: parts[0]),
                platform: .claude,
                client: .cli,
                model: model,
                provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: totals
            )
        }
    }

    private func loadPersistentCacheIfNeeded() {
        guard !didLoadPersistentCache else { return }
        didLoadPersistentCache = true
        guard let persistentCacheURL,
              let data = try? Data(contentsOf: persistentCacheURL),
              let persisted = try? JSONDecoder().decode(PersistedCache.self, from: data),
              persisted.version == 1,
              persisted.rootPath == root.standardizedFileURL.path else { return }
        cache = Dictionary(uniqueKeysWithValues: persisted.entries.map {
            (URL(fileURLWithPath: $0.key), $0.value)
        })
    }

    private func savePersistentCache() {
        guard let persistentCacheURL else { return }
        let payload = PersistedCache(
            version: 1,
            rootPath: root.standardizedFileURL.path,
            entries: Dictionary(uniqueKeysWithValues: cache.map { ($0.key.path, $0.value) })
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let directory = persistentCacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: persistentCacheURL, options: .atomic)
    }

    private func parseFile(
        _ url: URL,
        fallbackDay: String,
        startingAt: UInt64,
        seed: FileCache?
    ) -> (totalsByDay: [String: TokenTotals], deepSeekByDay: [String: TokenTotals], modelByDay: [String: TokenTotals])? {
        var totalsByDay = seed?.totalsByDay ?? [:]
        var deepSeekByDay = seed?.deepSeekByDay ?? [:]
        var modelByDay = seed?.modelByDay ?? [:]

        let didRead = JSONLReader.forEachLine(at: url, startingAt: startingAt) { data in
            autoreleasepool {
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let usage = Self.extractUsage(obj) else { return }

                let model = Self.extractModel(obj)
                let dayKey = Self.timestamp(obj).map { Self.dayKey(for: $0) } ?? fallbackDay
                let isDeepSeek = (model ?? "").lowercased().contains("deepseek")
                totalsByDay[dayKey, default: TokenTotals()] = totalsByDay[dayKey, default: TokenTotals()].adding(usage)
                let modelKey = "\(dayKey)\u{1F}\((model?.isEmpty == false ? model! : "unknown"))"
                modelByDay[modelKey, default: TokenTotals()] = modelByDay[modelKey, default: TokenTotals()].adding(usage)
                if isDeepSeek {
                    deepSeekByDay[dayKey, default: TokenTotals()] = deepSeekByDay[dayKey, default: TokenTotals()].adding(usage)
                }
            }
        }

        guard didRead else { return nil }
        return (totalsByDay, deepSeekByDay, modelByDay)
    }

    /// usage 字段在 assistant 消息的 message.usage 中；个别版本也可能直接挂在顶层。
    private static func extractUsage(_ obj: [String: Any]) -> TokenTotals? {
        let message = obj["message"] as? [String: Any]
        let usage = message?["usage"] as? [String: Any] ?? obj["usage"] as? [String: Any]
        guard let usage else { return nil }

        let intv: (String) -> Int = { key in
            (usage[key] as? NSNumber)?.intValue ?? 0
        }
        let input = intv("input_tokens")
        let cacheRead = intv("cache_read_input_tokens")
        let cacheWrite = intv("cache_creation_input_tokens")
        let output = intv("output_tokens")
        guard input + cacheRead + cacheWrite + output > 0 else { return nil }

        var totals = TokenTotals()
        // Claude 的 input_tokens 不含缓存，统一口径时把缓存读/写并入 input。
        totals.input = input + cacheRead + cacheWrite
        totals.cachedInput = cacheRead
        totals.cacheWriteInput = cacheWrite
        totals.output = output
        return totals
    }

    private static func extractModel(_ obj: [String: Any]) -> String? {
        if let message = obj["message"] as? [String: Any], let model = message["model"] as? String {
            return model
        }
        return obj["model"] as? String
    }

    private static func timestamp(_ obj: [String: Any]) -> Date? {
        guard let raw = obj["timestamp"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        return basic.date(from: raw)
    }

    private static func dayKey(for date: Date) -> String {
        DailyTokenUsage.dayKey(for: date)
    }

    private static func day(from key: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key) ?? .now
    }

    private static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    private static func defaultPersistentCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("claude-session-token-cache-v1.json")
    }
}
