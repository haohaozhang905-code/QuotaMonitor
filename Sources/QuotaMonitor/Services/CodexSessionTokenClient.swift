import Foundation

/// 从本地 Codex 会话日志解析按天 token 用量。
///
/// 数据来源：`~/.codex/sessions/<年>/<月>/<日>/*.jsonl` 与
/// `~/.codex/archived_sessions/rollout-*.jsonl`（Codex 归档旧会话时移动至此）。
/// 每行 `payload.info.total_token_usage` 是 per-session 累计量，取相邻两行的差得到
/// 单次请求增量；按该行 `timestamp` 的本地日期归日、按该行模型归 DeepSeek，
/// 与 cc-switch / DeepSeek 后台的逐请求口径一致（跨午夜会话会正确拆分）。
///
/// 用 actor 持有 mtime 增量缓存，避免每隔刷新周期全量重扫所有历史会话文件。
actor CodexSessionTokenClient {
    private struct CachedUsage: Codable, Equatable {
        let mtime: Date
        let fileSize: Int
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
        let processedByteCount: Int?
        let lastTotals: TokenTotals?
        let lastDayKey: String?
        let currentModel: String?

        func matches(mtime candidateMtime: Date, fileSize candidateSize: Int) -> Bool {
            fileSize == candidateSize
                && abs(mtime.timeIntervalSinceReferenceDate - candidateMtime.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    private struct PersistedCache: Codable {
        let version: Int
        let rootPath: String
        let entries: [String: CachedUsage]
    }

    private var cache: [URL: CachedUsage] = [:]
    private var didLoadPersistentCache = false
    private let root: URL
    private let persistentCacheURL: URL?

    init(root: URL? = nil, persistentCacheURL: URL? = nil) {
        let resolvedRoot = root ?? Self.defaultRoot()
        self.root = resolvedRoot
        if let persistentCacheURL {
            self.persistentCacheURL = persistentCacheURL
        } else if root == nil {
            self.persistentCacheURL = Self.defaultPersistentCacheURL()
        } else {
            // 测试或自定义数据源默认不落入正式应用缓存，避免相互污染。
            self.persistentCacheURL = nil
        }
    }

    func fetch() -> [DailyTokenUsage] {
        (try? fetchSnapshot().history) ?? []
    }

    /// 只统计模型名包含 deepseek 的请求增量。
    func fetch(modelFilter: String?) -> [DailyTokenUsage] {
        guard modelFilter?.lowercased().contains("deepseek") == true else { return fetch() }
        return (try? fetchSnapshot().deepSeekHistory) ?? []
    }

    /// 返回按日期和实际模型拆分的用量，供 Token 看板的“按模型”视图使用。
    func fetchBuckets() -> [TokenUsageBucket] {
        (try? fetchSnapshot().buckets) ?? []
    }

    func fetchSnapshot() throws -> TokenSourceSnapshot {
        TokenSourceSnapshot(buckets: try aggregateBuckets())
    }

    private func aggregateBuckets() throws -> [TokenUsageBucket] {
        loadPersistentCacheIfNeeded()
        var buckets: [TokenUsageBucket] = []
        var newCache: [URL: CachedUsage] = [:]
        for root in Self.sessionRoots(from: self.root) {
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else { throw TokenSourceReadError.unreadableRoot(root) }
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
                let parsed: [String: TokenTotals]
                let cached = cache[url]
                if let cached, cached.matches(mtime: mtime, fileSize: fileSize) {
                    newCache[url] = cached
                    parsed = cached.modelByDay
                } else {
                    let canContinue = cached?.processedByteCount == cached?.fileSize
                        && fileSize > (cached?.fileSize ?? 0)
                        && JSONLReader.isLineBoundary(at: cached?.fileSize ?? 0, in: url)
                    let startingAt = canContinue ? UInt64(cached?.fileSize ?? 0) : 0
                    let seed = canContinue ? cached : nil
                    guard let result = parseFile(
                        url,
                        fallbackDay: Self.dayComponents(from: url),
                        startingAt: startingAt,
                        seed: seed
                    ) else {
                        // 活跃日志可能在写入边界暂时无法解析；保留上一份文件汇总。
                        guard let cached = cache[url] else { continue }
                        newCache[url] = cached
                        buckets.append(contentsOf: Self.makeBuckets(from: cached.modelByDay))
                        continue
                    }
                    if result.modelByDay.isEmpty, let cached {
                        newCache[url] = cached
                        parsed = cached.modelByDay
                        buckets.append(contentsOf: Self.makeBuckets(from: parsed))
                        continue
                    }
                    let entry = CachedUsage(
                        mtime: mtime,
                        fileSize: fileSize,
                        totalsByDay: result.totalsByDay,
                        deepSeekByDay: result.deepSeekByDay,
                        modelByDay: result.modelByDay,
                        processedByteCount: fileSize,
                        lastTotals: result.lastTotals,
                        lastDayKey: result.lastDayKey,
                        currentModel: result.currentModel
                    )
                    newCache[url] = entry
                    parsed = entry.modelByDay
                }
                buckets.append(contentsOf: Self.makeBuckets(from: parsed))
            }
            if enumerationError != nil { throw TokenSourceReadError.unreadableRoot(root) }
        }
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
                platform: .codex,
                client: .cli,
                model: model,
                provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: totals
            )
        }
    }

    /// 历史会话解析结果跨启动保存；活跃文件按 mtime + 大小自动失效。
    /// 缓存只包含日期、模型与 token 汇总，不保存会话正文。
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

    private struct ParsedFile {
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
        let lastTotals: TokenTotals?
        let lastDayKey: String?
        let currentModel: String?
    }

    /// 逐行取累计量差值得到单次请求增量。活跃日志只从上次字节游标继续读取。
    private func parseFile(
        _ url: URL,
        fallbackDay: Date?,
        startingAt: UInt64,
        seed: CachedUsage?
    ) -> ParsedFile? {
        var lastTotals = seed?.lastTotals
        var lastDayKey = seed?.lastDayKey
        // 模型出现在 payload.state.model（状态行），增量读取时延续上次模型上下文。
        var currentModel = seed?.currentModel
        let fallbackDayKey = fallbackDay.map { DailyTokenUsage.dayKey(for: $0) }
        var totalsByDay = seed?.totalsByDay ?? [:]
        var deepSeekByDay = seed?.deepSeekByDay ?? [:]
        var modelByDay = seed?.modelByDay ?? [:]

        let didRead = JSONLReader.forEachLine(at: url, startingAt: startingAt) { data in
            autoreleasepool {
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                if let model = Self.extractModel(obj) {
                    currentModel = model
                }
                guard let totals = Self.extractTokenUsage(obj) else { return }

                let delta: TokenTotals
                if let last = lastTotals {
                    delta = totals.subtracting(last)
                } else {
                    delta = totals
                }
                lastTotals = totals
                guard delta.hasAnyUsage else { return }

                let dayKey: String
                if let raw = obj["timestamp"] as? String,
                   let date = Self.parseTimestamp(raw) {
                    dayKey = DailyTokenUsage.dayKey(for: date)
                } else if let lastDayKey {
                    dayKey = lastDayKey
                } else if let fallbackDayKey {
                    dayKey = fallbackDayKey
                } else {
                    return
                }
                lastDayKey = dayKey

                totalsByDay[dayKey, default: TokenTotals()] = totalsByDay[dayKey, default: TokenTotals()].adding(delta)
                let model = currentModel ?? ""
                let modelKey = "\(dayKey)\u{1F}\(model.isEmpty ? "unknown" : model)"
                modelByDay[modelKey, default: TokenTotals()] = modelByDay[modelKey, default: TokenTotals()].adding(delta)
                if model.lowercased().contains("deepseek") {
                    deepSeekByDay[dayKey, default: TokenTotals()] = deepSeekByDay[dayKey, default: TokenTotals()].adding(delta)
                }
            }
        }

        guard didRead else { return nil }
        return ParsedFile(
            totalsByDay: totalsByDay,
            deepSeekByDay: deepSeekByDay,
            modelByDay: modelByDay,
            lastTotals: lastTotals,
            lastDayKey: lastDayKey,
            currentModel: currentModel
        )
    }

    private static func extractModel(_ obj: [String: Any]) -> String? {
        guard let payload = obj["payload"] as? [String: Any] else { return nil }
        if let state = payload["state"] as? [String: Any] {
            if let model = state["model"] as? String { return model }
            if let personality = state["personality"] as? [String: Any],
               let model = personality["model"] as? String {
                return model
            }
        }
        if let info = payload["info"] as? [String: Any], let model = info["model"] as? String {
            return model
        }
        return payload["model"] as? String
    }

    private static func extractTokenUsage(_ obj: [String: Any]) -> TokenTotals? {
        guard let payload = obj["payload"] as? [String: Any],
              let info = payload["info"] as? [String: Any],
              let tu = info["total_token_usage"] as? [String: Any] else { return nil }
        let intv: (String) -> Int = { key in
            (tu[key] as? NSNumber)?.intValue ?? 0
        }
        var totals = TokenTotals()
        totals.input = intv("input_tokens")
        totals.cachedInput = intv("cached_input_tokens")
        totals.cacheWriteInput = intv("cache_write_input_tokens")
        totals.output = intv("output_tokens")
        totals.reasoning = intv("reasoning_output_tokens")
        if totals.reasoning == 0 { totals.reasoning = intv("reasoning_tokens") }
        return totals
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        return basic.date(from: raw)
    }

    private static func defaultRoot() -> URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func defaultPersistentCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("codex-session-token-cache-v1.json")
    }

    /// 会话目录与归档目录的并集；归档目录存在才加入。
    private static func sessionRoots(from root: URL) -> [URL] {
        let candidates = [
            root.appendingPathComponent("sessions", isDirectory: true),
            root.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        return candidates.filter { candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    /// 从路径的 <年>/<月>/<日> 段，或归档文件名前缀 rollout-YYYY-MM-DD，
    /// 还原本地零点日期，作为缺少时间戳行的兜底。
    private static func dayComponents(from url: URL) -> Date? {
        let name = url.lastPathComponent
        if name.hasPrefix("rollout-") {
            let parts = name.split(separator: "-").map(String.init)
            if parts.count >= 4,
               let year = Int(parts[1]),
               let month = Int(parts[2]),
               let day = Int(parts[3].prefix(while: { $0.isNumber })) {
                var components = DateComponents(year: year, month: month, day: day)
                components.timeZone = TimeZone.current
                return Calendar.current.date(from: components)
            }
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let yi = parts.firstIndex(where: { $0.count == 4 && (Int($0) ?? 0) > 2000 }),
              yi + 2 < parts.count,
              let y = Int(parts[yi]), let m = Int(parts[yi + 1]), let d = Int(parts[yi + 2]) else { return nil }
        var components = DateComponents(year: y, month: m, day: d)
        components.timeZone = TimeZone.current
        return Calendar.current.date(from: components)
    }

    private static func day(from key: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key) ?? .now
    }
}
