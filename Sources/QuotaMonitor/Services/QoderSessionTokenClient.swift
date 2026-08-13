import Foundation

/// 读取 Qoder CLI 与 Qoder Desktop / Work 的本地会话记录。
///
/// 两种日志格式会同时保存同一次消息的副本：CLI 事件流以 `request_id` 标识，
/// Desktop / Work 转录以 `message.id` 标识。扫描完成后按这些稳定 ID 去重，
/// 不把 `turn.finished` 这类汇总事件再次算作一次模型请求。
actor QoderSessionTokenClient {
    private enum Format: Sendable {
        case eventLog
        case transcript
    }

    private struct Root: Sendable {
        let url: URL
        let format: Format
        let client: TokenClient
    }

    private struct UsageRecord: Codable, Equatable {
        let id: String
        let bucket: TokenUsageBucket
    }

    private struct FileCache: Codable, Equatable {
        let mtime: Date
        let fileSize: Int
        let records: [UsageRecord]

        func matches(mtime candidate: Date, fileSize size: Int) -> Bool {
            fileSize == size && abs(mtime.timeIntervalSinceReferenceDate - candidate.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    private struct PersistedCache: Codable {
        let version: Int
        let entries: [String: FileCache]
    }

    private let roots: [Root]
    private let persistentCacheURL: URL?
    private var cache: [URL: FileCache] = [:]
    private var didLoadPersistentCache = false

    init(home: URL? = nil, persistentCacheURL: URL? = nil) {
        let home = home ?? FileManager.default.homeDirectoryForCurrentUser
        roots = [
            Root(url: home.appendingPathComponent(".qoder/logs/sessions", isDirectory: true), format: .eventLog, client: .cli),
            Root(
                url: home.appendingPathComponent("Library/Application Support/Qoder/SharedClientCache/cli/projects", isDirectory: true),
                format: .transcript,
                client: .desktop
            )
        ]
        self.persistentCacheURL = persistentCacheURL ?? Self.defaultPersistentCacheURL()
    }

    func fetchSnapshot() throws -> TokenSourceSnapshot {
        loadPersistentCacheIfNeeded()
        var newCache: [URL: FileCache] = [:]
        var records: [UsageRecord] = []
        var visited: Set<URL> = []

        for root in roots where FileManager.default.fileExists(atPath: root.url.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
                guard visited.insert(url).inserted,
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = values.contentModificationDate,
                      let fileSize = values.fileSize else { continue }
                let entry: FileCache
                if let cached = cache[url], cached.matches(mtime: mtime, fileSize: fileSize) {
                    entry = cached
                } else if let parsed = Self.parse(url: url, format: root.format, client: root.client, fallbackDate: mtime) {
                    entry = FileCache(mtime: mtime, fileSize: fileSize, records: parsed)
                } else if let cached = cache[url] {
                    // 正在写入的 JSONL 暂时不完整时，保留上一次正确的聚合值。
                    entry = cached
                } else {
                    continue
                }
                newCache[url] = entry
                records.append(contentsOf: entry.records)
            }
        }

        let changed = cache != newCache
        cache = newCache
        if changed { savePersistentCache() }

        var seen: Set<String> = []
        let buckets = records.compactMap { seen.insert($0.id).inserted ? $0.bucket : nil }
        return TokenSourceSnapshot(buckets: buckets)
    }

    private func loadPersistentCacheIfNeeded() {
        guard !didLoadPersistentCache else { return }
        didLoadPersistentCache = true
        guard let persistentCacheURL,
              let data = try? Data(contentsOf: persistentCacheURL),
              let payload = try? JSONDecoder().decode(PersistedCache.self, from: data),
              payload.version == 1 else { return }
        cache = Dictionary(uniqueKeysWithValues: payload.entries.map { (URL(fileURLWithPath: $0.key), $0.value) })
    }

    private func savePersistentCache() {
        guard let persistentCacheURL,
              let data = try? JSONEncoder().encode(PersistedCache(version: 1, entries: Dictionary(uniqueKeysWithValues: cache.map { ($0.key.path, $0.value) }))) else { return }
        try? FileManager.default.createDirectory(at: persistentCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: persistentCacheURL, options: .atomic)
    }

    private static func parse(
        url: URL,
        format: Format,
        client: TokenClient,
        fallbackDate: Date
    ) -> [UsageRecord]? {
        var records: [UsageRecord] = []
        let didRead = JSONLReader.forEachLine(at: url) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            switch format {
            case .eventLog:
                guard object["type"] as? String == "model.response.completed",
                      let requestID = object["request_id"] as? String,
                      let usage = object["data"] as? [String: Any],
                      let totals = totals(in: usage) else { return }
                records.append(UsageRecord(
                    id: "event|\(requestID)",
                    bucket: makeBucket(
                        totals: totals,
                        model: usage["model"] as? String,
                        date: date(in: object) ?? fallbackDate,
                        client: client
                    )
                ))
            case .transcript:
                guard object["type"] as? String == "assistant",
                      let message = object["message"] as? [String: Any],
                      let messageID = message["id"] as? String,
                      let usage = message["usage"] as? [String: Any],
                      let totals = totals(in: usage) else { return }
                records.append(UsageRecord(
                    id: "transcript|\(messageID)",
                    bucket: makeBucket(
                        totals: totals,
                        model: message["model"] as? String ?? usage["model"] as? String,
                        date: date(in: object) ?? fallbackDate,
                        client: client
                    )
                ))
            }
        }
        return didRead ? records : nil
    }

    private static func makeBucket(totals: TokenTotals, model: String?, date: Date, client: TokenClient) -> TokenUsageBucket {
        let model = TokenModelName.canonical(model)
        let hour = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
        return TokenUsageBucket(
            bucketStart: hour,
            platform: .qoder,
            client: client,
            model: model,
            provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
            totals: totals
        )
    }

    private static func totals(in object: [String: Any]) -> TokenTotals? {
        let input = number(in: object, keys: ["input_tokens", "prompt_tokens"])
        let output = number(in: object, keys: ["output_tokens", "completion_tokens"])
        let cacheRead = number(in: object, keys: ["cache_read_input_tokens"])
        let cacheWrite = number(in: object, keys: ["cache_creation_input_tokens"])
        guard input + output + cacheRead + cacheWrite > 0 else { return nil }
        var totals = TokenTotals()
        totals.input = input + cacheRead + cacheWrite
        totals.cachedInput = cacheRead
        totals.cacheWriteInput = cacheWrite
        totals.output = output
        return totals
    }

    private static func number(in object: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.intValue }
            if let text = object[key] as? String, let value = Int(text) { return value }
        }
        return 0
    }

    private static func date(in object: [String: Any]) -> Date? {
        for key in ["timestamp", "ts"] {
            guard let raw = object[key] as? String else { continue }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let basic = ISO8601DateFormatter()
            if let date = basic.date(from: raw) { return date }
        }
        return nil
    }

    private static func defaultPersistentCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("qoder-session-token-cache-v1.json")
    }
}
