import Foundation

/// 从 WorkBuddy 本地 trace 文件解析按天 token 用量。
///
/// 数据来源：`~/.workbuddy/traces/<pid>/trace_*.json`，每个工作流一个文件。
/// 文件很大（含完整对话）。旧版本的头部 `trace` 对象带汇总；新版本把
/// 每次模型调用的 usage 放在 generation span 的 toolOutput 中。本客户端
/// 只提取这些汇总字段，不保存或展示对话正文。
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
    private let headerReadLimit = 64 * 1024
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
              let summary = try? Self.traceDecoder().decode(TraceSummary.self, from: traceData) else { return nil }

        let dayKey = Self.dayKey(for: summary.startedAt)
        if summary.totalTokens > 0 {
            var totals = TokenTotals()
            totals.input = summary.modelInfo?.totalInputTokens
                ?? max(summary.totalTokens - (summary.modelInfo?.totalOutputTokens ?? 0), 0)
            totals.output = summary.modelInfo?.totalOutputTokens ?? 0
            totals.cachedInput = summary.modelInfo?.totalCachedTokens ?? 0
            let model = summary.modelInfo?.models?.joined(separator: " + ") ?? "unknown"
            let isDeepSeek = model.lowercased().contains("deepseek")
            return (
                [dayKey: totals],
                isDeepSeek ? [dayKey: totals] : [:],
                ["\(dayKey)\u{1F}\(model)": totals]
            )
        }

        // 新版 WorkBuddy 的 trace.totalTokens 可能为 0，实际 usage 在 generation span 的
        // toolOutput 字符串里；用定向分块扫描，避免把完整对话 JSON 一次性读入内存。
        return Self.parseGenerationUsages(
            at: url,
            fallbackDay: dayKey
        )
    }

    private struct GenerationUsage {
        let date: Date?
        let model: String
        let totals: TokenTotals
    }

    private struct GenerationUsageScanner {
        private var buffer = Data()
        private var bufferStart = 0
        private var lastMarkerOffset = -1
        private let contextLimit = 8 * 1024

        mutating func consume(_ chunk: Data, final: Bool = false) -> [GenerationUsage] {
            buffer.append(chunk)
            let bytes = Array(buffer)
            var found: [GenerationUsage] = []
            var cursor = max(0, lastMarkerOffset - bufferStart - 16)

            while let marker = Self.findUsageMarker(in: bytes, from: cursor) {
                let absoluteOffset = bufferStart + marker
                cursor = marker + 1
                if absoluteOffset <= lastMarkerOffset { continue }

                let start = max(0, marker - contextLimit)
                let end = min(bytes.count, marker + contextLimit)
                let context = Data(bytes[start..<end])
                guard let usage = WorkBuddyTraceClient.parseGenerationUsage(
                    context: context,
                    usageMarkerOffset: marker - start,
                    isFinal: final || end < bytes.count
                ) else {
                    // The usage object may be split at the current chunk boundary. Keep it
                    // for the next pass; non-usage matches are skipped by the marker shape.
                    if !final { break }
                    continue
                }
                found.append(usage)
                lastMarkerOffset = absoluteOffset
            }

            // Keep enough overlap for a marker and its surrounding model/created fields.
            let keep = contextLimit * 2
            if buffer.count > keep {
                let remove = buffer.count - keep
                buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: remove))
                bufferStart += remove
            }
            return found
        }

        private static func findUsageMarker(in bytes: [UInt8], from start: Int) -> Int? {
            let markers: [[UInt8]] = [
                Array("\"usage\":{".utf8),
                Array("\\\"usage\\\":{".utf8)
            ]
            var best: Int?
            for marker in markers {
                let lowerBound = max(0, start)
                let upperBound = bytes.count - marker.count
                guard marker.count <= bytes.count, lowerBound <= upperBound else { continue }
                for index in lowerBound...upperBound {
                    if Array(bytes[index..<(index + marker.count)]) == marker,
                       best == nil || index < best! {
                        best = index
                        break
                    }
                }
            }
            return best
        }
    }

    private static func parseGenerationUsages(
        at url: URL,
        fallbackDay: String
    ) -> (totalsByDay: [String: TokenTotals], deepSeekByDay: [String: TokenTotals], modelByDay: [String: TokenTotals])? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var scanner = GenerationUsageScanner()
        var usages: [GenerationUsage] = []
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            usages.append(contentsOf: scanner.consume(chunk))
        }
        usages.append(contentsOf: scanner.consume(Data(), final: true))
        guard !usages.isEmpty else { return nil }

        var totalsByDay: [String: TokenTotals] = [:]
        var deepSeekByDay: [String: TokenTotals] = [:]
        var modelByDay: [String: TokenTotals] = [:]
        for usage in usages {
            let dayKey = usage.date.map(Self.dayKey(for:)) ?? fallbackDay
            let model = usage.model.isEmpty ? "unknown" : usage.model
            totalsByDay[dayKey, default: TokenTotals()] = totalsByDay[dayKey, default: TokenTotals()].adding(usage.totals)
            let modelKey = "\(dayKey)\u{1F}\(model)"
            modelByDay[modelKey, default: TokenTotals()] = modelByDay[modelKey, default: TokenTotals()].adding(usage.totals)
            if model.lowercased().contains("deepseek") {
                deepSeekByDay[dayKey, default: TokenTotals()] = deepSeekByDay[dayKey, default: TokenTotals()].adding(usage.totals)
            }
        }
        return (totalsByDay, deepSeekByDay, modelByDay)
    }

    private static func parseGenerationUsage(
        context: Data,
        usageMarkerOffset: Int,
        isFinal: Bool
    ) -> GenerationUsage? {
        let bytes = Array(context)
        guard usageMarkerOffset >= 0, usageMarkerOffset < bytes.count else { return nil }
        let prefix = String(decoding: Data(bytes[..<usageMarkerOffset]), as: UTF8.self)
            .replacingOccurrences(of: "\\\"", with: "\"")
        let usageText = String(decoding: Data(bytes[usageMarkerOffset...]), as: UTF8.self)
            .replacingOccurrences(of: "\\\"", with: "\"")

        guard let input = integerValue(named: "prompt_tokens", in: usageText),
              let output = integerValue(named: "completion_tokens", in: usageText),
              input + output > 0 else {
            return nil
        }

        let model = stringValue(named: "model", in: prefix)
            ?? stringValue(named: "model", in: String(decoding: context, as: UTF8.self).replacingOccurrences(of: "\\\"", with: "\""))
            ?? "unknown"
        let created = integerValue(named: "created", in: prefix)
        var totals = TokenTotals()
        totals.input = input
        totals.cachedInput = integerValue(named: "cached_tokens", in: usageText) ?? 0
        totals.output = output
        totals.reasoning = integerValue(named: "reasoning_tokens", in: usageText) ?? 0
        let date = created.map { raw -> Date in
            let seconds = raw > 10_000_000_000 ? Double(raw) / 1000 : Double(raw)
            return Date(timeIntervalSince1970: seconds)
        }
        _ = isFinal
        return GenerationUsage(date: date, model: model, totals: totals)
    }

    private static func integerValue(named name: String, in text: String) -> Int? {
        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: name))\\\"\\s*:\\s*(-?\\d+)"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private static func stringValue(named name: String, in text: String) -> String? {
        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: name))\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
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
