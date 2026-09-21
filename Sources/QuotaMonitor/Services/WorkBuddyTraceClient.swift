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
actor WorkBuddyTraceClient: LocalTokenSnapshotProviding {
    private struct GenerationUsageRecord: Codable, Equatable {
        let offset: Int
        let date: Date?
        let model: String
        let totals: TokenTotals
    }

    private struct FileCache: LocalTokenScanCacheEntry {
        let mtime: Date
        let fileSize: Int
        let modelByDay: [String: TokenTotals]
        let processedByteCount: Int?
        let generationUsages: [GenerationUsageRecord]?
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
        self.persistentCacheURL = root == nil
            ? LocalTokenScanSupport.defaultCacheURL(fileName: "workbuddy-trace-cache-v1.json")
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
            accepts: { $0.lastPathComponent.hasPrefix("trace_") && $0.pathExtension == "json" },
            parse: { [self] url, mtime, fileSize, _, cached in
                parseFile(url, mtime: mtime, fileSize: fileSize, cached: cached)
            },
            emptyEntry: { mtime, fileSize in
                FileCache(
                    mtime: mtime,
                    fileSize: fileSize,
                    modelByDay: [:],
                    processedByteCount: fileSize,
                    generationUsages: []
                )
            },
            output: {
                LocalTokenScanSupport.modelBuckets(
                    from: $0.modelByDay,
                    platform: .workbuddy,
                    client: .desktop,
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
            return FileCache(
                mtime: mtime,
                fileSize: fileSize,
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
        var modelByDay: [String: TokenTotals] = [:]
        for usage in usages {
            let usageDay = usage.date.map(Self.dayKey(for:)) ?? dayKey
            let model = usage.model.isEmpty ? "unknown" : usage.model
            let usageBucket = usage.date.map(TokenUsageBucket.bucketKey(for:)) ?? usageDay
            let modelKey = "\(usageBucket)\u{1F}\(model)"
            modelByDay[modelKey, default: TokenTotals()] = modelByDay[modelKey, default: TokenTotals()].adding(usage.totals)
        }
        return FileCache(
            mtime: mtime,
            fileSize: fileSize,
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
                if Task.isCancelled { return [] }
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
            guard !Task.isCancelled else { return nil }
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
            if let date = LocalTokenScanSupport.iso8601Date(from: raw) { return date }
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

    private static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".workbuddy", isDirectory: true)
            .appendingPathComponent("traces", isDirectory: true)
    }

}
