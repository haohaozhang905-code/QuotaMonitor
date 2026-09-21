import Foundation

/// 从本地 Claude Code 会话转录解析 token 用量；历史总量按天汇总，模型桶保留到小时。
///
/// 数据来源：`~/.claude/projects/**/*.jsonl`，逐行 JSON，assistant 消息的
/// `message.usage` 含 input/cache_creation/cache_read/output 各 token 数，
/// `message.model` 记录实际模型（用户切换 cc-switch 后会出现 deepseek-v4-flash）。
///
/// 统一口径：`input` = input_tokens + cache_read + cache_creation（Claude 的
/// input_tokens 不含缓存），cachedInput 单独列示，total = input + output。
///
/// 用 actor 持有 mtime 增量缓存，避免每次刷新全量重扫历史转录。
actor ClaudeSessionTokenClient: LocalTokenSnapshotProviding {
    private struct FileCache: LocalTokenScanCacheEntry {
        let mtime: Date
        let fileSize: Int
        let modelByDay: [String: TokenTotals]
        let processedByteCount: Int?
    }

    private var cache: [URL: FileCache] = [:]
    private var didLoadPersistentCache = false
    private let root: URL
    private let persistentCacheURL: URL?

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        self.persistentCacheURL = root == nil
            ? LocalTokenScanSupport.defaultCacheURL(fileName: "claude-session-token-cache-v1.json")
            : nil
    }

    func snapshotBuckets() throws -> [TokenUsageBucket] {
        LocalTokenScanSupport.loadCacheIfNeeded(
            into: &cache, didLoad: &didLoadPersistentCache,
            at: persistentCacheURL, version: 2, root: root
        )
        let result = try LocalTokenScanSupport.scanSingleRoot(
            at: root,
            cache: cache,
            accepts: { $0.pathExtension == "jsonl" },
            parse: { [self] url, mtime, fileSize, offset, cached in
                guard let parsed = parseFile(
                    url,
                    fallbackDay: Self.dayKey(for: mtime),
                    startingAt: offset ?? 0,
                    seed: offset == nil ? nil : cached
                ), !parsed.isEmpty || cached == nil else { return nil }
                return FileCache(
                    mtime: mtime,
                    fileSize: fileSize,
                    modelByDay: parsed,
                    processedByteCount: fileSize
                )
            },
            output: {
                LocalTokenScanSupport.modelBuckets(
                    from: $0.modelByDay,
                    platform: .claude,
                    client: .cli,
                    invalidDatePolicy: .useNow
                )
            }
        )
        cache = result.cache
        LocalTokenScanSupport.saveCacheIfChanged(cache, changed: result.changed, at: persistentCacheURL, version: 2, root: root)
        return TokenUsageBucket.combining(result.output)
    }

    private func parseFile(
        _ url: URL,
        fallbackDay: String,
        startingAt: UInt64,
        seed: FileCache?
    ) -> [String: TokenTotals]? {
        var modelByDay = seed?.modelByDay ?? [:]

        let didRead = JSONLReader.forEachLine(at: url, startingAt: startingAt) { data in
            autoreleasepool {
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let usage = Self.extractUsage(obj) else { return }

                let model = Self.extractModel(obj)
                let timestamp = Self.timestamp(obj)
                let dayKey = timestamp.map { Self.dayKey(for: $0) } ?? fallbackDay
                let bucketKey = timestamp.map(TokenUsageBucket.bucketKey(for:)) ?? dayKey
                let modelKey = "\(bucketKey)\u{1F}\((model?.isEmpty == false ? model! : "unknown"))"
                modelByDay[modelKey, default: TokenTotals()] = modelByDay[modelKey, default: TokenTotals()].adding(usage)
            }
        }

        guard didRead else { return nil }
        return modelByDay
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
        return LocalTokenScanSupport.iso8601Date(from: raw)
    }

    private static func dayKey(for date: Date) -> String {
        DailyTokenUsage.dayKey(for: date)
    }

    private static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

}
