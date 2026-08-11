import Foundation

/// 从 WorkBuddy 本地 trace 文件解析按天 token 用量。
///
/// 数据来源：`~/.workbuddy/traces/<pid>/trace_*.json`，每个工作流一个文件。
/// 文件很大（含完整对话），但头部第一个 `trace` 对象就带汇总：
/// startedAt/endedAt、totalTokens、modelInfo(models/totalInputTokens/
/// totalOutputTokens/totalCachedTokens)。本客户端只读取文件前 8KB 并截取
/// 该汇总对象，不读取对话内容。
///
/// 统一口径：total = totalInputTokens + totalOutputTokens（input 已含缓存），
/// cached 单独列示，与 Codex 会话口径一致。
actor WorkBuddyTraceClient {
    private struct FileCache {
        let mtime: Date
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
    }

    private struct TraceSummary: Decodable {
        let startedAt: Date
        let totalTokens: Int
        /// 早期版本的 trace 头部没有 modelInfo（只有 totalTokens），
        /// 解码时用 totalTokens 兜底，保证总量不丢。
        let modelInfo: ModelInfo?

        struct ModelInfo: Decodable {
            let models: [String]?
            let totalInputTokens: Int?
            let totalOutputTokens: Int?
            let totalCachedTokens: Int?
        }

        enum CodingKeys: String, CodingKey {
            case startedAt
            case totalTokens
            case modelInfo
        }
    }

    private var cache: [URL: FileCache] = [:]
    private let headerReadLimit = 8 * 1024
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
    }

    func fetch() -> [DailyTokenUsage] {
        aggregate(deepSeekOnly: false)
    }

    /// 只统计模型列表包含 deepseek 的 trace。
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
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("trace_") && url.pathExtension == "json" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = values.contentModificationDate else { continue }
            let modelByDay: [String: TokenTotals]
            if let cached = cache[url], cached.mtime == mtime {
                modelByDay = cached.modelByDay
            } else {
                guard let parsed = parseFile(url) else { continue }
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
                let model = parts[1]
                buckets.append(TokenUsageBucket(
                    bucketStart: Self.day(from: parts[0]),
                    platform: .workbuddy,
                    client: .desktop,
                    model: model,
                    provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
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

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("trace_"), url.pathExtension == "json" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = values.contentModificationDate else { continue }

            let buckets: [String: TokenTotals]
            if let cached = cache[url], cached.mtime == mtime {
                newCache[url] = cached
                buckets = deepSeekOnly ? cached.deepSeekByDay : cached.totalsByDay
            } else {
                guard let parsed = parseFile(url) else { continue }
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

    private func parseFile(_ url: URL) -> (totalsByDay: [String: TokenTotals], deepSeekByDay: [String: TokenTotals], modelByDay: [String: TokenTotals])? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headerReadLimit),
              !data.isEmpty,
              let traceJSON = Self.extractTraceObject(from: String(decoding: data, as: UTF8.self)),
              let traceData = traceJSON.data(using: .utf8),
              let summary = try? Self.traceDecoder().decode(TraceSummary.self, from: traceData),
              summary.totalTokens > 0 else { return nil }

        let dayKey = Self.dayKey(for: summary.startedAt)
        let modelInfo = summary.modelInfo
        var totals = TokenTotals()
        // modelInfo 缺失时把 totalTokens 全部记入 input，总量口径仍为 input + output。
        totals.input = modelInfo?.totalInputTokens
            ?? max(summary.totalTokens - (modelInfo?.totalOutputTokens ?? 0), 0)
        totals.output = modelInfo?.totalOutputTokens ?? 0
        totals.cachedInput = modelInfo?.totalCachedTokens ?? 0

        let isDeepSeek = (modelInfo?.models ?? []).contains {
            $0.lowercased().contains("deepseek")
        }
        let model = modelInfo?.models?.joined(separator: " + ") ?? "unknown"
        return (
            [dayKey: totals],
            isDeepSeek ? [dayKey: totals] : [:],
            ["\(dayKey)\u{1F}\(model)": totals]
        )
    }

    /// 从头部的 `"trace":{...}` 起始截取平衡的 JSON 对象（跳过字符串与转义）。
    private static func extractTraceObject(from text: String) -> String? {
        guard let marker = text.range(of: "\"trace\"") else { return nil }
        guard let start = text.range(of: "{", range: marker.upperBound..<text.endIndex) else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        for index in text[start.lowerBound...].indices {
            let char = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }
            if char == "\"" {
                inString = true
            } else if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start.lowerBound...index])
                }
            }
        }
        return nil
    }

    private static func traceDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let basic = ISO8601DateFormatter()
            if let date = basic.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid trace timestamp"
            )
        }
        return decoder
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
            .appendingPathComponent(".workbuddy", isDirectory: true)
            .appendingPathComponent("traces", isDirectory: true)
    }
}
