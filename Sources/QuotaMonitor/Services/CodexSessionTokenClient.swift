import Foundation

/// 只读解析 Codex 会话日志；历史总量按天汇总，模型明细保留到小时。
///
/// 数据来源：`~/.codex/sessions/<年>/<月>/<日>/*.jsonl` 与
/// `~/.codex/archived_sessions/rollout-*.jsonl`，以及对应 `.jsonl.zst` 压缩文件。
/// 优先使用 `payload.info.last_token_usage` 的请求级用量；缺失时，
/// 对相邻 `total_token_usage` 累计值取差。按记录时间归入本地日期，跨午夜拆分。
/// 同一会话的普通、压缩及归档副本只读一份；fork 通过首条 `session_meta`
/// 识别父会话，排除双方累计用量序列的共同前缀，只计 fork 后新增的请求。
///
/// 文件未变时复用汇总；普通日志追加时续读，压缩文件变更时完整重算。
/// 仅写入汇总缓存，不解压回源目录，也不修改源日志。
actor CodexSessionTokenClient: LocalTokenSnapshotProviding {
    private struct CachedUsage: LocalTokenScanCacheEntry {
        let mtime: Date
        let fileSize: Int
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
        let processedByteCount: Int?
        let lastTotals: TokenTotals?
        let lastDayKey: String?
        let currentModel: String?
        let sessionID: String?
        let forkedFromID: String?
        /// Fork 文件中已继承的累计 usage 记录数；nil 表示尚未解析出父子关系。
        let inheritedUsageCount: Int?
        /// 旧 V5 缓存没有此字段，按普通 JSONL 处理。
        let isCompressed: Bool?
        /// 1 表示已按当前口径校准；旧缓存缺失此字段时，从源日志完整重算。
        let aggregationRevision: Int?

    }

    private struct SessionIdentity: Equatable {
        let sessionID: String
        let forkedFromID: String?
    }

    private struct SessionFile {
        let url: URL
        let mtime: Date
        let fileSize: Int
        let identity: SessionIdentity?
        let fallbackDay: Date?

        var isCompressed: Bool { url.pathExtension == "zst" }
        var cacheKey: URL { isCompressed ? url.deletingPathExtension() : url }

        var deduplicationKeys: [String] {
            var keys = ["path:\(cacheKey.path)"]
            if let identity { keys.append("session:\(identity.sessionID)") }
            let name = cacheKey.lastPathComponent
            if name.hasPrefix("rollout-") { keys.append("rollout:\(name)") }
            return keys
        }
    }

    private var cache: [URL: CachedUsage] = [:]
    private var didLoadPersistentCache = false
    private let root: URL
    private let persistentCacheURL: URL?
    private let fractionalTimestampFormatter: ISO8601DateFormatter
    private let basicTimestampFormatter: ISO8601DateFormatter
    private let bucketKeyFormatter: DateFormatter

    /// 先在原始字节上筛掉消息正文、工具输出等无关大行，再进入 JSONSerialization。
    /// 结构化 JSON key 没有反斜杠，因此不会命中正文字符串里的转义文本。
    private static let usageLineMarker = Data(#""total_token_usage":{"#.utf8)
    private static let modelValueMarker = Data(#""model":""#.utf8)
    private static let directStateModelMarker = Data(#""state":{"model":""#.utf8)
    private static let turnContextLineMarker = Data(#""type":"turn_context""#.utf8)
    private static let worldStateLineMarker = Data(#""type":"world_state""#.utf8)

    init(root: URL? = nil, persistentCacheURL: URL? = nil) {
        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalTimestampFormatter = fractionalTimestampFormatter
        self.basicTimestampFormatter = ISO8601DateFormatter()
        let bucketKeyFormatter = DateFormatter()
        bucketKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        bucketKeyFormatter.timeZone = .current
        bucketKeyFormatter.dateFormat = "yyyy-MM-dd-HH"
        self.bucketKeyFormatter = bucketKeyFormatter

        let resolvedRoot = root ?? CodexEnvironment.homeDirectory
        self.root = resolvedRoot
        if let persistentCacheURL {
            self.persistentCacheURL = persistentCacheURL
        } else if root == nil {
            self.persistentCacheURL = LocalTokenScanSupport.defaultCacheURL(
                fileName: "codex-session-token-cache-v3.json"
            )
        } else {
            // 测试或自定义数据源默认不落入正式应用缓存，避免相互污染。
            self.persistentCacheURL = nil
        }
    }

    /// 历史会话缓存只保存日期、模型和 Token 汇总，不保存会话正文。
    func snapshotBuckets() throws -> [TokenUsageBucket] {
        LocalTokenScanSupport.loadCacheIfNeeded(
            into: &cache, didLoad: &didLoadPersistentCache,
            at: persistentCacheURL, version: 5, root: root
        )
        var buckets: [TokenUsageBucket] = []
        var newCache: [URL: CachedUsage] = [:]
        var usageSequences: [URL: [TokenTotals]] = [:]
        let discoveredFiles = try discoverSessionFiles()
        let cachedBySessionID = Dictionary(
            cache.values.compactMap { entry -> (String, CachedUsage)? in
                entry.sessionID.map { ($0, entry) }
            }, uniquingKeysWith: { first, _ in first }
        )
        let filesBySessionID = Dictionary(
            discoveredFiles.compactMap { file -> (String, URL)? in
                guard let sessionID = file.identity?.sessionID else { return nil }
                return (sessionID, file.url)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let files = Self.parentFirst(discoveredFiles, filesBySessionID: filesBySessionID)

        for file in files {
            try Task.checkCancellation()
            let cached = cache[file.cacheKey] ?? file.identity.flatMap { cachedBySessionID[$0.sessionID] }
            let canAppend = !file.isCompressed && cached?.isCompressed != true
                && cached?.aggregationRevision == 1 && cache[file.cacheKey] != nil
            let appendOffset = canAppend ? LocalTokenScanSupport.appendOffset(
                currentFileSize: file.fileSize,
                cachedFileSize: cached?.fileSize,
                processedByteCount: cached?.processedByteCount,
                file: file.url
            ) : nil
            let canContinue = appendOffset != nil
            if let cached,
               cached.matches(mtime: file.mtime, fileSize: file.fileSize),
               (cached.isCompressed ?? false) == file.isCompressed,
               Self.canReuse(cached: cached, identity: file.identity) {
                newCache[file.cacheKey] = cached
                buckets.append(contentsOf: Self.makeBuckets(from: cached.modelByDay))
                continue
            }

            var parentUsageSequence: [TokenTotals]?
            var inheritedUsageCount: Int?
            if let parentID = file.identity?.forkedFromID {
                if canContinue, let cachedBoundary = cached?.inheritedUsageCount {
                    inheritedUsageCount = cachedBoundary
                } else {
                    guard let parentURL = filesBySessionID[parentID] else {
                        // 找不到父会话时不能把复制的完整历史当成新增用量。
                        continue
                    }
                    parentUsageSequence = Self.usageSequence(in: parentURL, cache: &usageSequences)
                    guard parentUsageSequence != nil else {
                        if parentURL.pathExtension == "zst" { throw TokenSourceReadError.unreadableRoot(parentURL) }
                        continue
                    }
                }
            } else {
                inheritedUsageCount = 0
            }

            let startingAt = appendOffset ?? 0
            let seed = canContinue ? cached : nil
            let parsed = parseFile(
                file.url,
                fallbackDay: file.fallbackDay,
                startingAt: startingAt,
                seed: seed,
                parentUsageSequence: startingAt == 0 ? parentUsageSequence : nil
            )
            try Task.checkCancellation()
            guard let result = parsed else {
                // 活跃日志可能在写入边界暂时无法解析；保留上一份文件汇总。
                guard let cached else {
                    if file.isCompressed { throw TokenSourceReadError.unreadableRoot(file.url) }
                    continue
                }
                newCache[file.cacheKey] = cached
                buckets.append(contentsOf: Self.makeBuckets(from: cached.modelByDay))
                continue
            }
            if result.modelByDay.isEmpty, let cached, !result.sawValidJSON {
                newCache[file.cacheKey] = cached
                buckets.append(contentsOf: Self.makeBuckets(from: cached.modelByDay))
                continue
            }
            if let sequence = result.usageSequence {
                usageSequences[file.url] = sequence
            }
            if startingAt == 0 {
                inheritedUsageCount = result.inheritedUsageCount
            }
            let entry = CachedUsage(
                mtime: file.mtime,
                fileSize: file.fileSize,
                totalsByDay: result.totalsByDay,
                deepSeekByDay: result.deepSeekByDay,
                modelByDay: result.modelByDay,
                processedByteCount: file.isCompressed ? nil : file.fileSize,
                lastTotals: result.lastTotals,
                lastDayKey: result.lastDayKey,
                currentModel: result.currentModel,
                sessionID: file.identity?.sessionID,
                forkedFromID: file.identity?.forkedFromID,
                inheritedUsageCount: inheritedUsageCount,
                isCompressed: file.isCompressed,
                aggregationRevision: 1
            )
            newCache[file.cacheKey] = entry
            buckets.append(contentsOf: Self.makeBuckets(from: entry.modelByDay))
        }
        let cacheChanged = cache != newCache
        cache = newCache
        LocalTokenScanSupport.saveCacheIfChanged(cache, changed: cacheChanged, at: persistentCacheURL, version: 5, root: root)
        return TokenUsageBucket.combining(buckets)
    }

    private static func makeBuckets(from modelByDay: [String: TokenTotals]) -> [TokenUsageBucket] {
        LocalTokenScanSupport.modelBuckets(from: modelByDay, platform: .codex, client: .cli)
    }

    private struct ParsedFile {
        let totalsByDay: [String: TokenTotals]
        let deepSeekByDay: [String: TokenTotals]
        let modelByDay: [String: TokenTotals]
        let lastTotals: TokenTotals?
        let lastDayKey: String?
        let currentModel: String?
        let sawValidJSON: Bool
        let usageSequence: [TokenTotals]?
        let inheritedUsageCount: Int
    }

    private struct ParsedTokenUsage {
        let cumulative: TokenTotals
        let request: TokenTotals?
    }

    /// 优先取请求级用量，缺失时用累计量差值；仅普通日志可从完整行边界续读。
    private func parseFile(
        _ url: URL,
        fallbackDay: Date?,
        startingAt: UInt64,
        seed: CachedUsage?,
        parentUsageSequence: [TokenTotals]?
    ) -> ParsedFile? {
        var lastTotals = seed?.lastTotals
        var lastDayKey = seed?.lastDayKey
        // 模型出现在 payload.state.model（状态行），增量读取时延续上次模型上下文。
        var currentModel = seed?.currentModel
        let fallbackDayKey = fallbackDay.map { DailyTokenUsage.dayKey(for: $0) }
        var totalsByDay = seed?.totalsByDay ?? [:]
        var deepSeekByDay = seed?.deepSeekByDay ?? [:]
        var modelByDay = seed?.modelByDay ?? [:]
        var usageRecordCount = 0
        var sawValidJSON = false
        var usageSequence: [TokenTotals]? = startingAt == 0 ? [] : nil
        var inheritedUsageCount = seed?.inheritedUsageCount ?? 0
        var isMatchingInheritedPrefix = parentUsageSequence != nil

        let didRead = JSONLReader.forEachLine(
            at: url,
            startingAt: startingAt,
            containingAnyOf: [
                [Self.usageLineMarker],
                [Self.directStateModelMarker],
                [Self.turnContextLineMarker, Self.modelValueMarker],
                [Self.worldStateLineMarker, Self.modelValueMarker]
            ]
        ) { data in
            autoreleasepool {
                if data.range(of: Self.usageLineMarker) == nil {
                    guard data.first == 0x7B, data.last == 0x7D else { return }
                    sawValidJSON = true
                    if let model = Self.extractModelValue(from: data) {
                        currentModel = model
                    }
                    return
                }
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                sawValidJSON = true
                if let model = Self.extractModel(obj) {
                    currentModel = model
                }
                guard let usage = Self.extractTokenUsage(obj) else { return }
                let totals = usage.cumulative

                usageSequence?.append(totals)
                let inherited: Bool
                if isMatchingInheritedPrefix,
                   let parentUsageSequence,
                   usageRecordCount < parentUsageSequence.count,
                   totals == parentUsageSequence[usageRecordCount] {
                    inherited = true
                    inheritedUsageCount += 1
                } else {
                    inherited = false
                    isMatchingInheritedPrefix = false
                }
                usageRecordCount += 1

                let delta = usage.request ?? (lastTotals.map { totals.subtracting($0) } ?? totals)
                lastTotals = totals
                if inherited { return }
                guard delta.hasAnyUsage else { return }

                let dayKey: String
                let bucketKey: String
                if let raw = obj["timestamp"] as? String,
                   let date = parseTimestamp(raw) {
                    dayKey = DailyTokenUsage.dayKey(for: date)
                    bucketKey = bucketKeyFormatter.string(from: date)
                } else if let lastDayKey {
                    dayKey = lastDayKey
                    bucketKey = lastDayKey
                } else if let fallbackDayKey {
                    dayKey = fallbackDayKey
                    bucketKey = fallbackDayKey
                } else {
                    return
                }
                lastDayKey = dayKey

                totalsByDay[dayKey, default: TokenTotals()] = totalsByDay[dayKey, default: TokenTotals()].adding(delta)
                let model = currentModel ?? ""
                let modelKey = "\(bucketKey)\u{1F}\(model.isEmpty ? "unknown" : model)"
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
            currentModel: currentModel,
            sawValidJSON: sawValidJSON,
            usageSequence: usageSequence,
            inheritedUsageCount: inheritedUsageCount
        )
    }

    private func discoverSessionFiles() throws -> [SessionFile] {
        var files: [SessionFile] = []
        for root in Self.sessionRoots(from: self.root) {
            var enumerationError: Error?
            guard let enumerator = LocalTokenScanSupport.enumerator(
                at: root,
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else { throw TokenSourceReadError.unreadableRoot(root) }
            for case let url as URL in enumerator where url.pathExtension == "jsonl"
                || (url.pathExtension == "zst" && url.deletingPathExtension().pathExtension == "jsonl") {
                let key = url.pathExtension == "zst" ? url.deletingPathExtension() : url
                let previous = cache[key]
                let metadata = LocalTokenScanSupport.fileMetadata(at: url)
                    ?? previous.map { (mtime: $0.mtime, fileSize: $0.fileSize) }
                guard let metadata else {
                    if url.pathExtension == "zst" { throw TokenSourceReadError.unreadableRoot(url) }
                    continue
                }
                // 首行暂时不可读时保留已知会话身份，避免同一副本被当成新会话。
                let identity = Self.readSessionIdentity(from: url) ?? previous?.sessionID.map {
                    SessionIdentity(sessionID: $0, forkedFromID: previous?.forkedFromID)
                }
                files.append(SessionFile(
                    url: url,
                    mtime: metadata.mtime,
                    fileSize: metadata.fileSize,
                    identity: identity,
                    fallbackDay: Self.dayComponents(from: url)
                ))
            }
            if enumerationError != nil { throw TokenSourceReadError.unreadableRoot(root) }
        }
        // 优先普通日志，同格式选修改时间较新的副本；路径用于稳定打破同时间平局。
        files.sort {
            if $0.isCompressed != $1.isCompressed { return !$0.isCompressed }
            if $0.mtime != $1.mtime { return $0.mtime > $1.mtime }
            return $0.url.path < $1.url.path
        }
        // 先合并路径、文件名与会话 ID 的关联，再选唯一副本。
        // 即使某份副本的首行暂不可读，普通/压缩文件也不会因此各算一次。
        var parents = Array(files.indices)
        func representative(_ index: Int) -> Int {
            var current = index
            while parents[current] != current { current = parents[current] }
            return current
        }
        var aliases: [String: Int] = [:]
        for index in files.indices {
            for key in files[index].deduplicationKeys {
                if let existing = aliases[key] {
                    parents[representative(index)] = representative(existing)
                }
                aliases[key] = index
            }
        }
        var seen: Set<Int> = []
        return files.indices.compactMap { seen.insert(representative($0)).inserted ? files[$0] : nil }
    }

    private static func canReuse(cached: CachedUsage, identity: SessionIdentity?) -> Bool {
        guard cached.aggregationRevision == 1,
              cached.sessionID == identity?.sessionID,
              cached.forkedFromID == identity?.forkedFromID else { return false }
        if identity?.forkedFromID != nil {
            return cached.inheritedUsageCount != nil
        }
        return true
    }

    private static func usageSequence(
        in url: URL,
        cache: inout [URL: [TokenTotals]]
    ) -> [TokenTotals]? {
        if let cached = cache[url] { return cached }
        var values: [TokenTotals] = []
        var sawInvalidJSON = false
        let didRead = JSONLReader.forEachLine(
            at: url,
            containingAnyOf: [[Self.usageLineMarker]]
        ) { data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                sawInvalidJSON = true
                return
            }
            guard let usage = extractTokenUsage(obj) else { return }
            values.append(usage.cumulative)
        }
        guard didRead, !sawInvalidJSON else { return nil }
        cache[url] = values
        return values
    }

    /// turn_context/world_state 往往携带数 MB 的指令与环境快照；模型名是简单字符串，
    /// 直接读取第一个结构化 model 字段即可，避免为一个字段构造整棵 JSON 对象树。
    private static func extractModelValue(from data: Data) -> String? {
        guard let marker = data.range(of: modelValueMarker) else { return nil }
        let start = marker.upperBound
        guard start < data.endIndex,
              let end = data[start...].firstIndex(of: 0x22),
              end > start else { return nil }
        return String(data: data[start..<end], encoding: .utf8)
    }

    /// 父会话先于子会话处理，使冷扫描可以在解析子文件时直接比较累计序列，
    /// 无需为了 fork 边界再把子文件完整读取一次。
    private static func parentFirst(
        _ files: [SessionFile],
        filesBySessionID: [String: URL]
    ) -> [SessionFile] {
        let filesByURL = Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0) })
        var ordered: [SessionFile] = []
        var visiting: Set<URL> = []
        var visited: Set<URL> = []

        func visit(_ file: SessionFile) {
            guard !visited.contains(file.url) else { return }
            guard visiting.insert(file.url).inserted else { return }
            if let parentID = file.identity?.forkedFromID,
               let parentURL = filesBySessionID[parentID],
               let parent = filesByURL[parentURL] {
                visit(parent)
            }
            visiting.remove(file.url)
            visited.insert(file.url)
            ordered.append(file)
        }

        for file in files { visit(file) }
        return ordered
    }

    private static func readSessionIdentity(from url: URL) -> SessionIdentity? {
        guard let firstLine = JSONLReader.firstLine(at: url),
              let obj = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              let sessionID = (payload["session_id"] as? String) ?? (payload["id"] as? String) else {
            return nil
        }
        // 普通会话的 session_id 与 id 相同；子会话有时会把 session_id
        // 保留为父线程 ID，而 payload.id 才是当前 JSONL 文件的会话 ID。
        let fileSessionID = (payload["id"] as? String) ?? sessionID
        let parentID = (payload["forked_from_id"] as? String)
            ?? (payload["parent_thread_id"] as? String)
        return SessionIdentity(sessionID: fileSessionID, forkedFromID: parentID)
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

    private static func extractTokenUsage(_ obj: [String: Any]) -> ParsedTokenUsage? {
        guard let payload = obj["payload"] as? [String: Any],
              let info = payload["info"] as? [String: Any],
              let tu = info["total_token_usage"] as? [String: Any] else { return nil }
        let cumulative = tokenTotals(from: tu)

        // 请求级字段也能记录压缩上下文等内部请求；此时累计值可能没有变化。
        let request: TokenTotals?
        if let last = info["last_token_usage"] as? [String: Any] {
            let parsed = tokenTotals(from: last)
            if parsed.hasAnyUsage {
                request = parsed
            } else if let total = (last["total_tokens"] as? NSNumber)?.intValue, total > 0 {
                // 部分内部请求只有 total_tokens。用 input 字段承载这笔总量，
                // 不据此推断真实的输入/输出拆分。
                var fallback = TokenTotals()
                fallback.input = total
                request = fallback
            } else {
                request = nil
            }
        } else {
            request = nil
        }
        return ParsedTokenUsage(cumulative: cumulative, request: request)
    }

    private static func tokenTotals(from object: [String: Any]) -> TokenTotals {
        let intv: (String) -> Int = { key in
            (object[key] as? NSNumber)?.intValue ?? 0
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

    private func parseTimestamp(_ raw: String) -> Date? {
        fractionalTimestampFormatter.date(from: raw) ?? basicTimestampFormatter.date(from: raw)
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
