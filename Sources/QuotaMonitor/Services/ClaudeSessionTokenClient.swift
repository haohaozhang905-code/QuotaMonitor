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
    private struct FileCache {
        let mtime: Date
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
    }

    private var cache: [URL: FileCache] = [:]
    private let maximumFileSize = 50 * 1024 * 1024
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
    }

    func fetch() -> [DailyTokenUsage] {
        aggregate(deepSeekOnly: false)
    }

    /// 只统计模型名包含 deepseek 的消息（与 Codex 客户端口径一致）。
    func fetch(modelFilter: String?) -> [DailyTokenUsage] {
        aggregate(deepSeekOnly: modelFilter?.lowercased().contains("deepseek") ?? false)
    }

    func fetchBuckets() -> [TokenUsageBucket] {
        var buckets: [TokenUsageBucket] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = values.contentModificationDate else { continue }
            let modelByDay: [String: TokenTotals]
            if let cached = cache[url], cached.mtime == mtime {
                modelByDay = cached.modelByDay
            } else {
                guard let parsed = parseFile(url, fallbackDay: Self.dayKey(for: mtime)) else { continue }
                let entry = FileCache(
                    mtime: mtime,
                    totalsByDay: parsed.totalsByDay,
                    deepSeekByDay: parsed.deepSeekByDay,
                    modelByDay: parsed.modelByDay
                )
                cache[url] = entry
                modelByDay = entry.modelByDay
            }
            for (key, totals) in modelByDay {
                let parts = key.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                buckets.append(TokenUsageBucket(
                    bucketStart: Self.day(from: parts[0]),
                    platform: .claude,
                    client: .cli,
                    model: parts[1],
                    provider: parts[1].lowercased().contains("deepseek") ? .deepseek : .official,
                    totals: totals
                ))
            }
        }
        return TokenUsageBucket.combining(buckets)
    }

    private func aggregate(deepSeekOnly: Bool) -> [DailyTokenUsage] {
        var newCache: [URL: FileCache] = [:]
        var perDay: [String: TokenTotals] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = values.contentModificationDate else { continue }

            let buckets: [String: TokenTotals]
            if let cached = cache[url], cached.mtime == mtime {
                newCache[url] = cached
                buckets = deepSeekOnly ? cached.deepSeekByDay : cached.totalsByDay
            } else {
                guard let parsed = parseFile(url, fallbackDay: Self.dayKey(for: mtime)) else { continue }
                let entry = FileCache(
                    mtime: mtime,
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

        cache = newCache
        return perDay.map { key, totals in
            DailyTokenUsage(day: Self.day(from: key), totals: totals)
        }
        .sorted { $0.day < $1.day }
    }

    private func parseFile(_ url: URL, fallbackDay: String) -> (totalsByDay: [String: TokenTotals], deepSeekByDay: [String: TokenTotals], modelByDay: [String: TokenTotals])? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= maximumFileSize else { return nil }
        var totalsByDay: [String: TokenTotals] = [:]
        var deepSeekByDay: [String: TokenTotals] = [:]
        var modelByDay: [String: TokenTotals] = [:]

        let didRead = JSONLReader.forEachLine(at: url) { data in
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

        guard didRead, !totalsByDay.isEmpty else { return nil }
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
}
