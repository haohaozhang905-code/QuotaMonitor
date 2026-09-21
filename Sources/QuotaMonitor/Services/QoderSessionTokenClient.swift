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

    private struct FileCache: LocalTokenScanCacheEntry {
        let mtime: Date
        let fileSize: Int
        let records: [UsageRecord]
        let processedByteCount: Int?

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
        self.persistentCacheURL = persistentCacheURL
            ?? LocalTokenScanSupport.defaultCacheURL(fileName: "qoder-session-token-cache-v1.json")
    }

    func fetchSnapshot() throws -> TokenSourceSnapshot {
        LocalTokenScanSupport.loadCacheIfNeeded(
            into: &cache, didLoad: &didLoadPersistentCache,
            at: persistentCacheURL, version: 1
        )
        var newCache: [URL: FileCache] = [:]
        var records: [UsageRecord] = []
        var visited: Set<URL> = []

        for root in roots where FileManager.default.fileExists(atPath: root.url.path) {
            let result = try LocalTokenScanSupport.scanSingleRoot(
                at: root.url,
                cache: cache,
                accepts: { $0.pathExtension.lowercased() == "jsonl" && visited.insert($0).inserted },
                parse: { url, mtime, fileSize, offset, cached in
                    guard let parsed = Self.parse(
                        url: url,
                        format: root.format,
                        client: root.client,
                        fallbackDate: mtime,
                        startingAt: Int(offset ?? 0)
                    ) else { return nil }
                    return FileCache(
                        mtime: mtime,
                        fileSize: fileSize,
                        records: offset == nil ? parsed : (cached?.records ?? []) + parsed,
                        processedByteCount: fileSize
                    )
                },
                enumerationFailure: .skipRoot,
                preserveCachedEntryWhenMetadataIsUnavailable: false,
                output: { $0.records }
            )
            newCache.merge(result.cache) { first, _ in first }
            records.append(contentsOf: result.output)
        }

        let changed = cache != newCache
        cache = newCache
        LocalTokenScanSupport.saveCacheIfChanged(cache, changed: changed, at: persistentCacheURL, version: 1)

        var seen: Set<String> = []
        let buckets = records.compactMap { seen.insert($0.id).inserted ? $0.bucket : nil }
        return TokenSourceSnapshot(buckets: buckets)
    }

    private static func parse(
        url: URL,
        format: Format,
        client: TokenClient,
        fallbackDate: Date,
        startingAt: Int
    ) -> [UsageRecord]? {
        var records: [UsageRecord] = []
        let didRead = JSONLReader.forEachLine(at: url, startingAt: UInt64(startingAt)) { data in
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
        let hour = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
        return TokenUsageBucket.modelBucket(
            at: hour, platform: .qoder, client: client, model: model, totals: totals
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
            if let date = LocalTokenScanSupport.iso8601Date(from: raw) { return date }
        }
        return nil
    }

}
