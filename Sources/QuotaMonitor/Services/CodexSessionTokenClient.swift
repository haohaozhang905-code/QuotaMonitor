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
    private struct CachedUsage: Codable {
        let mtime: Date
        let fileSize: Int
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]

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
        aggregate(modelFilter: nil)
    }

    /// 只统计模型名包含 deepseek 的请求增量。
    func fetch(modelFilter: String?) -> [DailyTokenUsage] {
        aggregate(modelFilter: modelFilter)
    }

    /// 返回按日期和实际模型拆分的用量，供 Token 看板的“按模型”视图使用。
    func fetchBuckets() -> [TokenUsageBucket] {
        aggregateBuckets()
    }

    private func aggregate(modelFilter: String?) -> [DailyTokenUsage] {
        loadPersistentCacheIfNeeded()
        var newCache: [URL: CachedUsage] = [:]
        var perDay: [String: TokenTotals] = [:]
        let deepSeekOnly = modelFilter?.lowercased().contains("deepseek") ?? false

        for root in Self.sessionRoots(from: self.root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = values.contentModificationDate,
                      let fileSize = values.fileSize else { continue }
                let fallbackDay = Self.dayComponents(from: url)

                let buckets: [String: TokenTotals]
                if let cached = cache[url], cached.matches(mtime: mtime, fileSize: fileSize) {
                    newCache[url] = cached
                    buckets = deepSeekOnly ? cached.deepSeekByDay : cached.totalsByDay
                } else {
                    guard let parsed = parseFile(url, fallbackDay: fallbackDay) else { continue }
                    let entry = CachedUsage(
                        mtime: mtime,
                        fileSize: fileSize,
                        totalsByDay: parsed.totalsByDay,
                        deepSeekByDay: parsed.deepSeekByDay,
                        modelByDay: parsed.modelByDay
                    )
                    newCache[url] = entry
                    buckets = deepSeekOnly ? entry.deepSeekByDay : entry.totalsByDay
                }

                for (dayKey, totals) in buckets {
                    if let existing = perDay[dayKey] {
                        perDay[dayKey] = existing.adding(totals)
                    } else {
                        perDay[dayKey] = totals
                    }
                }
            }
        }

        cache = newCache
        savePersistentCache()
        return perDay.map { key, totals in
            DailyTokenUsage(day: Self.day(from: key), totals: totals)
        }
        .sorted { $0.day < $1.day }
    }

    private func aggregateBuckets() -> [TokenUsageBucket] {
        loadPersistentCacheIfNeeded()
        var buckets: [TokenUsageBucket] = []
        var cacheChanged = false
        for root in Self.sessionRoots(from: self.root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = values.contentModificationDate,
                      let fileSize = values.fileSize else { continue }
                let parsed: [String: TokenTotals]
                if let cached = cache[url], cached.matches(mtime: mtime, fileSize: fileSize) {
                    parsed = cached.modelByDay
                } else {
                    guard let result = parseFile(url, fallbackDay: Self.dayComponents(from: url)) else { continue }
                    let entry = CachedUsage(
                        mtime: mtime,
                        fileSize: fileSize,
                        totalsByDay: result.totalsByDay,
                        deepSeekByDay: result.deepSeekByDay,
                        modelByDay: result.modelByDay
                    )
                    cache[url] = entry
                    cacheChanged = true
                    parsed = entry.modelByDay
                }
                for (key, totals) in parsed {
                    let parts = key.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { continue }
                    let day = Self.day(from: parts[0])
                    let model = parts[1]
                    buckets.append(TokenUsageBucket(
                        bucketStart: day,
                        platform: .codex,
                        client: .cli,
                        model: model,
                        provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                        totals: totals
                    ))
                }
            }
        }
        if cacheChanged { savePersistentCache() }
        return TokenUsageBucket.combining(buckets)
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

    /// 逐行取累计量差值得到单次请求增量，按行 timestamp 本地日归日、按行模型归 DeepSeek。
    private func parseFile(
        _ url: URL,
        fallbackDay: Date?
    ) -> (totalsByDay: [String: TokenTotals], deepSeekByDay: [String: TokenTotals], modelByDay: [String: TokenTotals])? {
        var lastTotals: TokenTotals?
        var lastDayKey: String?
        // 模型出现在 payload.state.model（状态行），需跨行跟踪当前生效模型。
        var currentModel: String?
        let fallbackDayKey = fallbackDay.map { DailyTokenUsage.dayKey(for: $0) }
        var totalsByDay: [String: TokenTotals] = [:]
        var deepSeekByDay: [String: TokenTotals] = [:]
        var modelByDay: [String: TokenTotals] = [:]

        let didRead = JSONLReader.forEachLine(at: url) { data in
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

        guard didRead, !totalsByDay.isEmpty else { return nil }
        return (totalsByDay, deepSeekByDay, modelByDay)
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
