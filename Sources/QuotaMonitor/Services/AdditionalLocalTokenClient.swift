import Foundation
import SQLite3

/// 可由同一套本地日志扫描器接入的 AI 工具。新增工具通常只需补一条定义和路径，
/// 不需要改动汇总、趋势或界面层；专用格式仍由各自的 client 处理。
struct LocalToolTokenSource: Hashable, Sendable {
    enum Format: String, Hashable, Sendable {
        case generic
        /// Kimi Desktop 的 wire.jsonl 同时记录步骤结束与 usage.record；仅后者是一条可计费请求。
        case kimiWire
        /// 千问办公同时写入 model.response.completed 与 turn.finished；前者是一条模型请求，后者是回合汇总。
        case qwenWork
        /// Trae Work 的 renderer.log 在 JSON 前带有日志前缀，仅解析含有明确 fee_usage 的行。
        case traeWork
    }

    let platform: TokenPlatform
    let roots: [String]
    let overrideEnvironment: String
    let format: Format
    let client: TokenClient

    init(
        platform: TokenPlatform,
        roots: [String],
        overrideEnvironment: String,
        format: Format = .generic,
        client: TokenClient = .cli
    ) {
        self.platform = platform
        self.roots = roots
        self.overrideEnvironment = overrideEnvironment
        self.format = format
        self.client = client
    }

    func resolvedRoots(home: URL, environment: [String: String]) -> [URL] {
        let override = environment[overrideEnvironment]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = (override?.isEmpty == false ? [override!] : []) + roots
        return paths.map { path in
            path.hasPrefix("/")
                ? URL(fileURLWithPath: path, isDirectory: true)
                : home.appendingPathComponent(path, isDirectory: true)
        }
    }

    /// README 中声明的本地用量来源。仅含可在本机读取会话、事件或数据库记录的工具；
    /// 余额/订阅额度 API（OpenRouter、Minimax 等）需要用户明确配置凭证后再单独接入。
    static let additional: [Self] = [
        .init(platform: .opencode, roots: [".local/share/opencode/storage/message", ".local/share/opencode"], overrideEnvironment: "QUOTAMONITOR_OPENCODE_HOME"),
        .init(platform: .hermes, roots: [".hermes"], overrideEnvironment: "HERMES_HOME"),
        .init(platform: .openclaw, roots: [".openclaw/agents"], overrideEnvironment: "QUOTAMONITOR_OPENCLAW_HOME"),
        // `~/.cursor/projects` 的转录会把用户粘贴的 JSON 原文保存在消息正文，
        // 不能把正文里长得像 token 的字段误算为用量；只读取 Cursor 同步缓存或结构化工作区记录。
        .init(platform: .cursor, roots: [".config/tokscale/cursor-cache", "Library/Application Support/Cursor/User/workspaceStorage"], overrideEnvironment: "QUOTAMONITOR_CURSOR_HOME"),
        .init(platform: .antigravity, roots: [".config/tokscale/antigravity-cache"], overrideEnvironment: "QUOTAMONITOR_ANTIGRAVITY_HOME"),
        .init(platform: .cline, roots: [".cline/data/sessions", "Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"], overrideEnvironment: "CLINE_HOME"),
        .init(platform: .kimi, roots: [".kimi/sessions", ".kimi-code/sessions"], overrideEnvironment: "KIMI_CODE_HOME"),
        .init(
            platform: .kimi,
            roots: ["Library/Application Support/kimi-desktop/daimon-share/daimon/runtime/kimi-code/home/sessions"],
            overrideEnvironment: "QUOTAMONITOR_KIMI_DESKTOP_HOME",
            format: .kimiWire,
            client: .desktop
        ),
        .init(platform: .qwen, roots: [".qwen/projects"], overrideEnvironment: "QUOTAMONITOR_QWEN_HOME"),
        .init(
            platform: .qwenWork,
            roots: [".qwenworkcn/logs/sessions"],
            overrideEnvironment: "QUOTAMONITOR_QWEN_WORK_HOME",
            format: .qwenWork,
            client: .desktop
        ),
        .init(
            platform: .traeWork,
            roots: ["Library/Application Support/TRAE SOLO CN/logs"],
            overrideEnvironment: "QUOTAMONITOR_TRAE_WORK_HOME",
            format: .traeWork,
            client: .desktop
        ),
        .init(platform: .grok, roots: [".grok/sessions", ".grok/logs"], overrideEnvironment: "GROK_HOME"),
        .init(platform: .copilot, roots: [".copilot", "Library/Application Support/Code/User/globalStorage/github.copilot-chat"], overrideEnvironment: "QUOTAMONITOR_COPILOT_HOME"),
        .init(platform: .pi, roots: [".pi/agent/sessions", ".omp/agent/sessions"], overrideEnvironment: "QUOTAMONITOR_PI_HOME"),
        .init(platform: .zed, roots: [".local/share/zed/threads"], overrideEnvironment: "QUOTAMONITOR_ZED_HOME"),
        .init(platform: .kilo, roots: ["Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/tasks"], overrideEnvironment: "QUOTAMONITOR_KILO_HOME"),
        .init(platform: .mimo, roots: [".local/share/mimocode"], overrideEnvironment: "QUOTAMONITOR_MIMO_HOME"),
        .init(platform: .zcode, roots: [".zcode/projects", ".zcode/cli"], overrideEnvironment: "QUOTAMONITOR_ZCODE_HOME"),
        .init(platform: .kiro, roots: [".kiro/sessions/cli", "Library/Application Support/Kiro/User/globalStorage"], overrideEnvironment: "QUOTAMONITOR_KIRO_HOME"),
        .init(platform: .codebuddy, roots: [".codebuddy/projects"], overrideEnvironment: "QUOTAMONITOR_CODEBUDDY_HOME"),
        .init(platform: .proma, roots: [".proma/agent-sessions"], overrideEnvironment: "QUOTAMONITOR_PROMA_HOME"),
        .init(platform: .reasonix, roots: [".reasonix/stats", ".reasonix/sessions", ".reasonix/projects"], overrideEnvironment: "REASONIX_HOME")
    ]
}

/// 面向新工具的保守通用解析器：读取本机 JSON、JSONL 和 SQLite 中结构化 usage，
/// 只采集 token 字段、模型和时间；不保留提示词、回答或项目内容。
actor AdditionalLocalTokenClient {
    private struct FileCache: Codable, Equatable {
        let mtime: Date
        let fileSize: Int
        let buckets: [TokenUsageBucket]
        let processedByteCount: Int?

        func matches(mtime candidate: Date, fileSize size: Int) -> Bool {
            fileSize == size && abs(mtime.timeIntervalSinceReferenceDate - candidate.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    private struct PersistedCache: Codable {
        let version: Int
        let entries: [String: FileCache]
    }

    private let sources: [LocalToolTokenSource]
    private let home: URL
    private let environment: [String: String]
    private let persistentCacheURL: URL?
    private var cache: [String: FileCache] = [:]
    private var didLoadCache = false

    init(
        sources: [LocalToolTokenSource] = LocalToolTokenSource.additional,
        home: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        persistentCacheURL: URL? = nil
    ) {
        self.sources = sources
        self.home = home ?? FileManager.default.homeDirectoryForCurrentUser
        self.environment = environment
        self.persistentCacheURL = persistentCacheURL ?? Self.defaultPersistentCacheURL()
    }

    func fetchSnapshots() throws -> [TokenSourceSnapshot] {
        loadPersistentCacheIfNeeded()
        var freshCache: [String: FileCache] = [:]
        var bucketsByPlatform: [TokenPlatform: [TokenUsageBucket]] = [:]
        var visited: Set<String> = []

        for source in sources {
            try Task.checkCancellation()
            for root in source.resolvedRoots(home: home, environment: environment) where FileManager.default.fileExists(atPath: root.path) {
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let url as URL in enumerator {
                    try Task.checkCancellation()
                    let ext = url.pathExtension.lowercased()
                    let cacheKey = Self.cacheKey(url: url, source: source)
                    guard ["json", "jsonl", "log", "db", "sqlite", "sqlite3"].contains(ext), visited.insert(cacheKey).inserted else { continue }
                    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                          let mtime = values.contentModificationDate,
                          let size = values.fileSize else { continue }
                    let cached = cache[cacheKey]
                    let buckets: [TokenUsageBucket]
                    if let cached = cache[cacheKey], cached.matches(mtime: mtime, fileSize: size) {
                        buckets = cached.buckets
                    } else {
                        let isLineFile = ["jsonl", "log"].contains(ext)
                        let canContinue = isLineFile
                            && cached?.processedByteCount == cached?.fileSize
                            && size > (cached?.fileSize ?? 0)
                            && JSONLReader.isLineBoundary(at: cached?.fileSize ?? 0, in: url)
                        let startingAt = canContinue ? cached?.fileSize ?? 0 : 0
                        guard let parsed = Self.parse(
                            url: url,
                            source: source,
                            fallbackDate: mtime,
                            startingAt: startingAt
                        ) else {
                            if let cached = cache[cacheKey] {
                                freshCache[cacheKey] = cached
                                bucketsByPlatform[source.platform, default: []].append(contentsOf: cached.buckets)
                            }
                            continue
                        }
                        buckets = canContinue
                            ? TokenUsageBucket.combining((cached?.buckets ?? []) + parsed)
                            : parsed
                    }
                    let entry = FileCache(
                        mtime: mtime,
                        fileSize: size,
                        buckets: buckets,
                        processedByteCount: size
                    )
                    freshCache[cacheKey] = entry
                    bucketsByPlatform[source.platform, default: []].append(contentsOf: buckets)
                }
            }
        }
        let cacheChanged = cache != freshCache
        cache = freshCache
        if cacheChanged { savePersistentCache() }
        return TokenPlatform.allCases.compactMap { platform in
            guard let buckets = bucketsByPlatform[platform], !buckets.isEmpty else { return nil }
            return TokenSourceSnapshot(buckets: buckets)
        }
    }

    private func loadPersistentCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let persistentCacheURL,
              let data = try? Data(contentsOf: persistentCacheURL),
              let payload = try? JSONDecoder().decode(PersistedCache.self, from: data),
              payload.version == 3 else { return }
        cache = payload.entries
    }

    private func savePersistentCache() {
        guard let persistentCacheURL,
              let data = try? JSONEncoder().encode(PersistedCache(version: 3, entries: cache)) else { return }
        try? FileManager.default.createDirectory(at: persistentCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: persistentCacheURL, options: .atomic)
    }

    private static func parse(
        url: URL,
        source: LocalToolTokenSource,
        fallbackDate: Date,
        startingAt: Int
    ) -> [TokenUsageBucket]? {
        if source.format == .kimiWire {
            return parseKimiWire(url: url, source: source, fallbackDate: fallbackDate, startingAt: startingAt)
        }
        if source.format == .qwenWork {
            return parseQwenWork(url: url, source: source, fallbackDate: fallbackDate, startingAt: startingAt)
        }
        if source.format == .traeWork {
            return parseTraeWork(url: url, source: source, fallbackDate: fallbackDate, startingAt: startingAt)
        }
        switch url.pathExtension.lowercased() {
        case "db", "sqlite", "sqlite3": return parseSQLite(url: url, source: source, fallbackDate: fallbackDate)
        case "jsonl", "log":
            var parsedBuckets: [TokenUsageBucket] = []
            let didRead = JSONLReader.forEachLine(at: url, startingAt: UInt64(startingAt)) { data in
                guard let value = try? JSONSerialization.jsonObject(with: data) else { return }
                parsedBuckets.append(contentsOf: buckets(in: value, source: source, fallbackDate: fallbackDate))
            }
            guard didRead else { return nil }
            return TokenUsageBucket.combining(parsedBuckets)
        default:
            guard let data = try? Data(contentsOf: url), data.count <= 32 * 1024 * 1024,
                  let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return TokenUsageBucket.combining(buckets(in: value, source: source, fallbackDate: fallbackDate))
        }
    }

    private static func buckets(in value: Any, source: LocalToolTokenSource, fallbackDate: Date) -> [TokenUsageBucket] {
        var result: [TokenUsageBucket] = []
        func scan(_ value: Any, model inheritedModel: String?, date inheritedDate: Date?, depth: Int) {
            guard depth < 24 else { return }
            if let values = value as? [Any] {
                values.forEach { scan($0, model: inheritedModel, date: inheritedDate, depth: depth + 1) }
                return
            }
            guard let object = value as? [String: Any] else { return }
            let model = string(in: object, keys: ["model", "model_name", "modelName", "model_id", "modelId"]) ?? inheritedModel
            let date = date(in: object) ?? inheritedDate
            if let usage = object["usage"] ?? object["token_usage"] ?? object["tokenUsage"] ?? object["fee_usage"], let totals = totals(in: usage) {
                append(totals: totals, model: model, date: date ?? fallbackDate)
            } else if let totals = totals(in: object) {
                append(totals: totals, model: model, date: date ?? fallbackDate)
            }
            for (key, child) in object where key != "usage" && key != "token_usage" && key != "tokenUsage" && key != "fee_usage" {
                scan(child, model: model, date: date, depth: depth + 1)
            }
        }
        func append(totals: TokenTotals, model: String?, date: Date) {
            guard totals.input + totals.output > 0 else { return }
            let normalizedModel = TokenModelName.canonical(model)
            let hour = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
            result.append(TokenUsageBucket(
                bucketStart: hour,
                platform: source.platform,
                client: source.client,
                model: normalizedModel,
                provider: normalizedModel.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: totals
            ))
        }
        scan(value, model: nil, date: nil, depth: 0)
        return result
    }

    private static func totals(in value: Any) -> TokenTotals? {
        guard let object = value as? [String: Any] else { return nil }
        let input = number(in: object, keys: ["input_tokens", "prompt_tokens", "inputTokens", "promptTokens"])
        let output = number(in: object, keys: ["output_tokens", "completion_tokens", "outputTokens", "completionTokens"])
        let total = number(in: object, keys: ["total_tokens", "totalTokens"])
        guard input > 0 || output > 0 || total > 0 else { return nil }
        let cached = number(in: object, keys: ["cache_read_input_tokens", "cached_input_tokens", "cached_tokens", "cacheReadTokens"])
        let cacheWrite = number(in: object, keys: ["cache_creation_input_tokens", "cache_write_input_tokens", "cacheWriteTokens"])
        var result = TokenTotals()
        result.input = input > 0 || output > 0 ? input : max(total - output, 0)
        result.output = output
        result.cachedInput = cached
        result.cacheWriteInput = cacheWrite
        return result
    }

    /// Kimi Desktop / Kimi Code 的一个回合有 `step.end` 与 `usage.record` 两类使用量事件；
    /// 前者是前者的镜像，故只读取 `usage.record`，避免每个回合重复统计。
    private static func parseKimiWire(
        url: URL,
        source: LocalToolTokenSource,
        fallbackDate: Date,
        startingAt: Int
    ) -> [TokenUsageBucket]? {
        guard url.pathExtension.lowercased() == "jsonl" else { return [] }
        var buckets: [TokenUsageBucket] = []
        let didRead = JSONLReader.forEachLine(at: url, startingAt: UInt64(startingAt)) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "usage.record",
                  let usage = object["usage"] as? [String: Any] else { return }
            let inputOther = number(in: usage, keys: ["inputOther"])
            let cacheRead = number(in: usage, keys: ["inputCacheRead"])
            let cacheWrite = number(in: usage, keys: ["inputCacheCreation"])
            let output = number(in: usage, keys: ["output"])
            guard inputOther + cacheRead + cacheWrite + output > 0 else { return }
            var totals = TokenTotals()
            totals.input = inputOther + cacheRead + cacheWrite
            totals.cachedInput = cacheRead
            totals.cacheWriteInput = cacheWrite
            totals.output = output
            let date = date(in: object) ?? fallbackDate
            let hour = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
            let model = TokenModelName.canonical(object["model"] as? String)
            buckets.append(TokenUsageBucket(
                bucketStart: hour,
                platform: source.platform,
                client: source.client,
                model: model,
                provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: totals
            ))
        }
        guard didRead else { return nil }
        return TokenUsageBucket.combining(buckets)
    }

    /// 千问办公的 session segment 同时保存每个模型请求和一个回合汇总。
    /// 只读取 model.response.completed，避免把 turn.finished 再加一遍。
    private static func parseQwenWork(
        url: URL,
        source: LocalToolTokenSource,
        fallbackDate: Date,
        startingAt: Int
    ) -> [TokenUsageBucket]? {
        guard url.pathExtension.lowercased() == "jsonl" else { return [] }
        var buckets: [TokenUsageBucket] = []
        let didRead = JSONLReader.forEachLine(at: url, startingAt: UInt64(startingAt)) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "model.response.completed",
                  let usage = object["data"] as? [String: Any],
                  let totals = totals(in: usage) else { return }
            // qwork 的 input_tokens 不含 cache_read/cache_creation，统一口径时把缓存并入 input。
            var normalizedTotals = totals
            normalizedTotals.input += totals.cachedInput + totals.cacheWriteInput
            let model = TokenModelName.canonical(string(in: usage, keys: ["model"]) ?? string(in: object, keys: ["model"]))
            let date = date(in: object) ?? fallbackDate
            let hour = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
            buckets.append(TokenUsageBucket(
                bucketStart: hour,
                platform: source.platform,
                client: source.client,
                model: model,
                provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: normalizedTotals
            ))
        }
        guard didRead else { return nil }
        return TokenUsageBucket.combining(buckets)
    }

    /// Trae Work 的 renderer.log 形如 `ISO 时间 [级别] ... {JSON}`，
    /// 只读取明确含有 fee_usage 的记录，避免把 prompt_max_tokens 等上限字段误当成消耗。
    private static func parseTraeWork(
        url: URL,
        source: LocalToolTokenSource,
        fallbackDate: Date,
        startingAt: Int
    ) -> [TokenUsageBucket]? {
        guard url.pathExtension.lowercased() == "log" else { return [] }
        var parsedBuckets: [TokenUsageBucket] = []
        let didRead = JSONLReader.forEachLine(at: url, startingAt: UInt64(startingAt)) { data in
            guard let line = String(data: data, encoding: .utf8), line.contains("\"fee_usage\""),
                  let start = line.firstIndex(of: "{"),
                  let jsonData = String(line[start...]).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: jsonData) else { return }
            let lineDate = traeLogDate(from: line) ?? fallbackDate
            parsedBuckets.append(contentsOf: buckets(in: value, source: source, fallbackDate: lineDate))
        }
        guard didRead else { return nil }
        return TokenUsageBucket.combining(parsedBuckets)
    }

    private static func traeLogDate(from line: String) -> Date? {
        guard let separator = line.range(of: " [") else { return nil }
        let raw = String(line[..<separator.lowerBound])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    private static func cacheKey(url: URL, source: LocalToolTokenSource) -> String {
        "\(url.path)|\(source.platform.rawValue)|\(source.format.rawValue)|\(source.client.rawValue)"
    }

    private static func number(in object: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let number = object[key] as? NSNumber { return number.intValue }
            if let text = object[key] as? String, let number = Int(text) { return number }
        }
        return 0
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        keys.compactMap { object[$0] as? String }.first(where: { !$0.isEmpty })
    }

    private static func date(in object: [String: Any]) -> Date? {
        for key in ["timestamp", "created_at", "createdAt", "created", "time", "ts", "updated_at"] {
            if let value = object[key] as? NSNumber {
                let seconds = value.doubleValue > 100_000_000_000 ? value.doubleValue / 1_000 : value.doubleValue
                return Date(timeIntervalSince1970: seconds)
            }
            if let value = object[key] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: value) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: value) { return date }
            }
        }
        return nil
    }

    private static func parseSQLite(url: URL, source: LocalToolTokenSource, fallbackDate: Date) -> [TokenUsageBucket]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { return nil }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)
        let tables = sqliteStrings(database: database, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            .filter { name in ["message", "session", "usage", "event", "trace", "chat", "log"].contains(where: { name.lowercased().contains($0) }) }
        var result: [TokenUsageBucket] = []
        for table in tables {
            let escaped = table.replacingOccurrences(of: "\"", with: "\"\"")
            guard let statement = prepare(database: database, sql: "SELECT * FROM \"\(escaped)\"") else { continue }
            defer { sqlite3_finalize(statement) }
            let count = Int(sqlite3_column_count(statement))
            let names = (0..<count).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                for index in 0..<count {
                    let column = Int32(index)
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: row[names[index]] = NSNumber(value: sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: row[names[index]] = NSNumber(value: sqlite3_column_double(statement, column))
                    case SQLITE_TEXT: row[names[index]] = sqlite3_column_text(statement, column).map { String(cString: $0) }
                    default: break
                    }
                }
                result.append(contentsOf: buckets(in: row, source: source, fallbackDate: fallbackDate))
                for value in row.values {
                    guard let text = value as? String, text.first == "{" || text.first == "[",
                          let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
                    result.append(contentsOf: buckets(in: json, source: source, fallbackDate: fallbackDate))
                }
            }
        }
        return TokenUsageBucket.combining(result)
    }

    private static func sqliteStrings(database: OpaquePointer, sql: String) -> [String] {
        guard let statement = prepare(database: database, sql: sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var strings: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) { strings.append(String(cString: value)) }
        }
        return strings
    }

    private static func prepare(database: OpaquePointer, sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }

    private static func defaultPersistentCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("additional-local-token-cache-v1.json")
    }
}
