import Foundation

/// 从 WorkBuddy 本地 trace 文件解析 token 用量；历史总量按天汇总，模型桶保留到小时。
///
/// 数据来源：`~/.workbuddy/traces/<pid>/trace_*.json`，每个工作流一个文件。
/// 文件很大（含完整对话）。旧版本的头部 `trace` 对象带汇总；新版本把
/// 每次模型调用的 usage 放在 generation span 的 toolOutput 中。本客户端
/// 只提取这些汇总字段，不保存或展示对话正文。
///
/// 统一口径：total = totalInputTokens + totalOutputTokens（input 已含缓存），
/// cached 单独列示，与 Codex 会话口径一致。
actor WorkBuddyTraceClient {
    private struct GenerationUsageRecord: Codable, Equatable {
        let offset: Int
        let date: Date?
        let model: String
        let totals: TokenTotals
    }

    private struct FileCache: Codable, Equatable {
        let mtime: Date
        let fileSize: Int
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
        let processedByteCount: Int?
        let generationUsages: [GenerationUsageRecord]?

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
    private var didLoadPersistentCache = false
    private let headerReadLimit = 64 * 1024
    private let generationOverlap = 1024 * 1024
    private let root: URL
    private let persistentCacheURL: URL?

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        self.persistentCacheURL = root == nil ? Self.defaultPersistentCacheURL() : nil
    }

    func fetch() -> [DailyTokenUsage] {
        (try? fetchSnapshot().history) ?? []
    }

    /// 只统计模型列表包含 deepseek 的 trace。
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
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("trace_") && url.pathExtension == "json" {
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
            if let cached = cache[url], cached.matches(mtime: mtime, fileSize: fileSize) {
                newCache[url] = cached
                modelByDay = cached.modelByDay
            } else if let entry = parseFile(
                url,
                mtime: mtime,
                fileSize: fileSize,
                cached: cache[url]
            ) {
                newCache[url] = entry
                modelByDay = entry.modelByDay
            } else if let cached = cache[url] {
                // 写入边界暂时不完整时继续展示该文件上一份有效结果。
                newCache[url] = cached
                modelByDay = cached.modelByDay
            } else {
                // 空 trace 或不含 usage 的 trace 也记入缓存；文件不变时不再反复解析。
                let entry = FileCache(
                    mtime: mtime,
                    fileSize: fileSize,
                    totalsByDay: [:],
                    deepSeekByDay: [:],
                    modelByDay: [:],
                    processedByteCount: fileSize,
                    generationUsages: []
                )
                newCache[url] = entry
                modelByDay = [:]
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
                bucketStart: TokenUsageBucket.date(fromBucketKey: parts[0]) ?? day(from: parts[0]),
                platform: .workbuddy,
                client: .desktop,
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
              persisted.version == 2,
              persisted.rootPath == root.standardizedFileURL.path else { return }
        cache = Dictionary(uniqueKeysWithValues: persisted.entries.map {
            (URL(fileURLWithPath: $0.key), $0.value)
        })
    }

    private func savePersistentCache() {
        guard let persistentCacheURL else { return }
        let payload = PersistedCache(
            version: 2,
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
        mtime: Date,
        fileSize: Int,
        cached: FileCache?
    ) -> FileCache? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headerReadLimit),
              !data.isEmpty,
              let traceJSON = Self.extractTraceObject(from: String(decoding: data, as: UTF8.self)),
              let traceData = traceJSON.data(using: .utf8),
              let summary = try? Self.traceDecoder().decode(TraceSummary.self, from: traceData) else { return nil }

            let dayKey = Self.dayKey(for: summary.startedAt)
            let bucketKey = TokenUsageBucket.bucketKey(for: summary.startedAt)
        if summary.totalTokens > 0 {
            var totals = TokenTotals()
            totals.input = summary.modelInfo?.totalInputTokens
                ?? max(summary.totalTokens - (summary.modelInfo?.totalOutputTokens ?? 0), 0)
            totals.output = summary.modelInfo?.totalOutputTokens ?? 0
            totals.cachedInput = summary.modelInfo?.totalCachedTokens ?? 0
            let model = summary.modelInfo?.models?.joined(separator: " + ") ?? "unknown"
            let isDeepSeek = model.lowercased().contains("deepseek")
            return FileCache(
                mtime: mtime,
                fileSize: fileSize,
                totalsByDay: [dayKey: totals],
                deepSeekByDay: isDeepSeek ? [dayKey: totals] : [:],
                modelByDay: ["\(bucketKey)\u{1F}\(model)": totals],
                processedByteCount: fileSize,
                generationUsages: nil
            )
        }

        // 新版 WorkBuddy 的 trace.totalTokens 可能为 0，实际 usage 在 generation span 的
        // toolOutput 字符串里；用定向分块扫描，避免把完整对话 JSON 一次性读入内存。
        let canContinue = cached?.generationUsages != nil
            && cached?.processedByteCount == cached?.fileSize
            && fileSize > (cached?.fileSize ?? 0)
        let startingAt = canContinue
            ? max(0, (cached?.fileSize ?? 0) - generationOverlap)
            : 0
        guard let parsedUsages = Self.parseGenerationUsages(
            at: url,
            startingAt: startingAt
        ) else { return nil }

        var usagesByOffset = Dictionary(
            uniqueKeysWithValues: (canContinue ? cached?.generationUsages ?? [] : []).map {
                ($0.offset, $0)
            }
        )
        for usage in parsedUsages {
            usagesByOffset[usage.offset] = GenerationUsageRecord(
                offset: usage.offset,
                date: usage.date,
                model: usage.model,
                totals: usage.totals
            )
        }
        let usages = usagesByOffset.values.sorted { $0.offset < $1.offset }
        var totalsByDay: [String: TokenTotals] = [:]
        var deepSeekByDay: [String: TokenTotals] = [:]
        var modelByDay: [String: TokenTotals] = [:]
        for usage in usages {
            let usageDay = usage.date.map(Self.dayKey(for:)) ?? dayKey
            let model = usage.model.isEmpty ? "unknown" : usage.model
            totalsByDay[usageDay, default: TokenTotals()] = totalsByDay[usageDay, default: TokenTotals()].adding(usage.totals)
            let usageBucket = usage.date.map(TokenUsageBucket.bucketKey(for:)) ?? usageDay
            let modelKey = "\(usageBucket)\u{1F}\(model)"
            modelByDay[modelKey, default: TokenTotals()] = modelByDay[modelKey, default: TokenTotals()].adding(usage.totals)
            if model.lowercased().contains("deepseek") {
                deepSeekByDay[usageDay, default: TokenTotals()] = deepSeekByDay[usageDay, default: TokenTotals()].adding(usage.totals)
            }
        }
        return FileCache(
            mtime: mtime,
            fileSize: fileSize,
            totalsByDay: totalsByDay,
            deepSeekByDay: deepSeekByDay,
            modelByDay: modelByDay,
            processedByteCount: fileSize,
            generationUsages: usages
        )
    }

    private struct GenerationUsage {
        let offset: Int
        let date: Date?
        let model: String
        let totals: TokenTotals
    }

    private struct GenerationUsageScanner {
        private var buffer = Data()
        private var bufferStart: Int
        private var lastMarkerOffset = -1
        private var nextSearchOffset = 0
        // model/created 位于响应头，usage 位于响应尾。保留有限的大窗口以覆盖长回复，
        // 同时仍避免把数百 MB trace 一次性载入内存。
        private let contextLimit = 512 * 1024

        init(initialOffset: Int = 0) {
            bufferStart = initialOffset
        }

        mutating func consume(_ chunk: Data, final: Bool = false) -> [GenerationUsage] {
            buffer.append(chunk)
            let bytes = buffer
            var found: [GenerationUsage] = []
            var cursor = max(0, nextSearchOffset - bufferStart)
            var waitingForMoreData = false

            while let marker = Self.findUsageMarker(in: bytes, from: cursor) {
                let absoluteOffset = bufferStart + marker
                cursor = marker + 1
                if absoluteOffset <= lastMarkerOffset { continue }

                let start = max(0, marker - contextLimit)
                let end = min(bytes.count, marker + contextLimit)
                let context = bytes.subdata(in: start..<end)
                guard let usage = WorkBuddyTraceClient.parseGenerationUsage(
                    context: context,
                    usageMarkerOffset: marker - start,
                    markerOffset: absoluteOffset,
                    isFinal: final || end < bytes.count
                ) else {
                    // The usage object may be split at the current chunk boundary. Keep it
                    // for the next pass; non-usage matches are skipped by the marker shape.
                    if !final && end == bytes.count {
                        nextSearchOffset = absoluteOffset
                        waitingForMoreData = true
                        break
                    }
                    nextSearchOffset = absoluteOffset + 1
                    continue
                }
                found.append(usage)
                lastMarkerOffset = absoluteOffset
                nextSearchOffset = absoluteOffset + 1
            }

            if !waitingForMoreData {
                // Preserve only enough overlap for a marker split across two chunks;
                // do not rescan the entire rolling buffer on every read.
                nextSearchOffset = max(nextSearchOffset, bufferStart + max(0, bytes.count - 16))
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

        private static func findUsageMarker(in bytes: Data, from start: Int) -> Int? {
            let markers: [Data] = [
                Data("\"usage\":{".utf8),
                Data("\\\"usage\\\":{".utf8)
            ]
            var best: Int?
            for marker in markers {
                let lowerBound = max(0, start)
                guard marker.count <= bytes.count, lowerBound <= bytes.count - marker.count else { continue }
                guard let range = bytes.range(of: marker, options: [], in: lowerBound..<bytes.count) else { continue }
                if best == nil || range.lowerBound < best! { best = range.lowerBound }
            }
            return best
        }
    }

    private static func parseGenerationUsages(
        at url: URL,
        startingAt: Int
    ) -> [GenerationUsage]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard (try? handle.seek(toOffset: UInt64(startingAt))) != nil else { return nil }
        var scanner = GenerationUsageScanner(initialOffset: startingAt)
        var usages: [GenerationUsage] = []
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            usages.append(contentsOf: scanner.consume(chunk))
        }
        usages.append(contentsOf: scanner.consume(Data(), final: true))
        return usages
    }

    private static func parseGenerationUsage(
        context: Data,
        usageMarkerOffset: Int,
        markerOffset: Int,
        isFinal: Bool
    ) -> GenerationUsage? {
        guard usageMarkerOffset >= 0, usageMarkerOffset < context.count else { return nil }
        let prefix = String(decoding: context.prefix(usageMarkerOffset), as: UTF8.self)
            .replacingOccurrences(of: "\\\"", with: "\"")
        guard let outputField = prefix.range(of: "\"toolOutput\"", options: .backwards) else { return nil }
        if let inputField = prefix.range(of: "\"toolInput\"", options: .backwards),
           inputField.lowerBound > outputField.lowerBound {
            return nil
        }
        let trailingText = String(decoding: context.dropFirst(usageMarkerOffset), as: UTF8.self)
            .replacingOccurrences(of: "\\\"", with: "\"")
        guard let usageText = balancedJSONObject(in: trailingText) else {
            // 当前 8 KB 上下文还没有覆盖完整 usage 对象时，等待下一块数据。
            _ = isFinal
            return nil
        }

        guard let input = integerValue(named: "prompt_tokens", in: usageText),
              let output = integerValue(named: "completion_tokens", in: usageText),
              input + output > 0 else {
            return nil
        }
        if let total = integerValue(named: "total_tokens", in: usageText), total != input + output {
            return nil
        }

        let normalizedContext = String(decoding: context, as: UTF8.self).replacingOccurrences(of: "\\\"", with: "\"")
        guard let model = stringValue(named: "model", in: prefix)
                ?? stringValue(named: "model", in: normalizedContext),
              let created = integerValue(named: "created", in: prefix)
                ?? integerValue(named: "created", in: normalizedContext) else { return nil }
        var totals = TokenTotals()
        totals.input = input
        totals.cachedInput = integerValue(named: "cached_tokens", in: usageText) ?? 0
        totals.output = output
        totals.reasoning = integerValue(named: "reasoning_tokens", in: usageText) ?? 0
        let seconds = created > 10_000_000_000 ? Double(created) / 1000 : Double(created)
        let date = Date(timeIntervalSince1970: seconds)
        return GenerationUsage(offset: markerOffset, date: date, model: model, totals: totals)
    }

    private static func balancedJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
        }
        return nil
    }

    private static func integerValue(named name: String, in text: String) -> Int? {
        guard let key = valueKey(named: name, in: text),
              let valueStart = valueStart(after: key, in: text) else { return nil }
        var index = valueStart
        var sign = 1
        if text[index] == "-" {
            sign = -1
            index = text.index(after: index)
        }
        let digitsStart = index
        while index < text.endIndex, text[index].isNumber {
            index = text.index(after: index)
        }
        guard index > digitsStart, let value = Int(text[digitsStart..<index]) else { return nil }
        return sign * value
    }

    private static func stringValue(named name: String, in text: String) -> String? {
        guard let key = valueKey(named: name, in: text),
              let valueStart = valueStart(after: key, in: text),
              text[valueStart] == "\"" else { return nil }
        var index = text.index(after: valueStart)
        var escaped = false
        var value = ""
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                value.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return value.isEmpty ? nil : value
            } else {
                value.append(character)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func valueKey(named name: String, in text: String) -> Range<String.Index>? {
        text.range(of: "\"\(name)\"")
            ?? text.range(of: "\\\"\(name)\\\"")
    }

    private static func valueStart(
        after key: Range<String.Index>,
        in text: String
    ) -> String.Index? {
        var index = key.upperBound
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == ":" else { return nil }
        index = text.index(after: index)
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        return index < text.endIndex ? index : nil
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

    private static func defaultPersistentCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("workbuddy-trace-cache-v1.json")
    }
}
