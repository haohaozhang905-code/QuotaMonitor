import Foundation

protocol LocalTokenSnapshotProviding: Actor {
    func snapshotBuckets() throws -> [TokenUsageBucket]
}

extension LocalTokenSnapshotProviding {
    func fetchSnapshot() throws -> TokenSourceSnapshot {
        TokenSourceSnapshot(buckets: try snapshotBuckets())
    }
}

protocol LocalTokenScanCacheEntry: Codable, Equatable {
    var mtime: Date { get }
    var fileSize: Int { get }
    var processedByteCount: Int? { get }
}

extension LocalTokenScanCacheEntry {
    func matches(mtime candidateMtime: Date, fileSize candidateSize: Int) -> Bool {
        fileSize == candidateSize
            && abs(mtime.timeIntervalSinceReferenceDate - candidateMtime.timeIntervalSinceReferenceDate) < 0.001
    }
}

/// Shared, format-neutral pieces used by local token scanners. Parsing and
/// source-specific cache payloads stay with their respective clients.
enum LocalTokenScanSupport {
    private struct CacheEnvelope<Entry: Codable>: Codable {
        let version: Int
        let rootPath: String?
        let entries: [String: Entry]
    }

    enum InvalidBucketDatePolicy {
        case useNow
        case omit
    }

    enum EnumerationFailurePolicy {
        case throwError
        case skipRoot
    }

    static func defaultCacheURL(fileName: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func iso8601Date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    static func scanSingleRoot<Entry: LocalTokenScanCacheEntry, Output>(
        at root: URL,
        cache: [URL: Entry],
        accepts: (URL) -> Bool,
        parse: (URL, Date, Int, UInt64?, Entry?) -> Entry?,
        emptyEntry: ((Date, Int) -> Entry?)? = nil,
        enumerationFailure: EnumerationFailurePolicy = .throwError,
        preserveCachedEntryWhenMetadataIsUnavailable: Bool = true,
        output: (Entry) -> [Output]
    ) throws -> (cache: [URL: Entry], output: [Output], changed: Bool) {
        try Task.checkCancellation()
        var nextCache: [URL: Entry] = [:]
        var outputs: [Output] = []
        var enumerationError: Error?
        guard let files = enumerator(at: root, errorHandler: { _, error in
            enumerationError = error
            return false
        }) else {
            if !FileManager.default.fileExists(atPath: root.path) { return (cache, [], false) }
            if enumerationFailure == .skipRoot { return ([:], [], !cache.isEmpty) }
            throw TokenSourceReadError.unreadableRoot(root)
        }

        for case let url as URL in files where accepts(url) {
            try Task.checkCancellation()
            let cached = cache[url]
            guard let metadata = fileMetadata(at: url) else {
                if preserveCachedEntryWhenMetadataIsUnavailable, let cached {
                    nextCache[url] = cached
                    outputs.append(contentsOf: output(cached))
                }
                continue
            }
            let (mtime, fileSize) = metadata
            let entry: Entry
            if let cached, cached.matches(mtime: mtime, fileSize: fileSize) {
                entry = cached
            } else {
                let offset = appendOffset(
                    currentFileSize: fileSize,
                    cachedFileSize: cached?.fileSize,
                    processedByteCount: cached?.processedByteCount,
                    file: url
                )
                if let parsed = parse(url, mtime, fileSize, offset, cached) {
                    entry = parsed
                } else if let cached {
                    entry = cached
                } else if let empty = emptyEntry?(mtime, fileSize) {
                    entry = empty
                } else {
                    continue
                }
            }
            nextCache[url] = entry
            outputs.append(contentsOf: output(entry))
        }
        if enumerationError != nil {
            if enumerationFailure == .throwError { throw TokenSourceReadError.unreadableRoot(root) }
            return ([:], [], !cache.isEmpty)
        }
        return (nextCache, outputs, cache != nextCache)
    }

    static func loadCache<Entry: Codable>(
        at url: URL?,
        version: Int,
        root: URL? = nil
    ) -> [URL: Entry]? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheEnvelope<Entry>.self, from: data),
              envelope.version == version else { return nil }
        if let root, envelope.rootPath != root.standardizedFileURL.path { return nil }
        return Dictionary(uniqueKeysWithValues: envelope.entries.map {
            (URL(fileURLWithPath: $0.key), $0.value)
        })
    }

    static func loadCacheIfNeeded<Entry: Codable>(
        into cache: inout [URL: Entry],
        didLoad: inout Bool,
        at url: URL?,
        version: Int,
        root: URL? = nil
    ) {
        guard !didLoad else { return }
        didLoad = true
        cache = loadCache(at: url, version: version, root: root) ?? [:]
    }

    static func saveCache<Entry: Codable>(
        _ entries: [URL: Entry],
        at url: URL?,
        version: Int,
        root: URL? = nil
    ) {
        guard let url else { return }
        let envelope = CacheEnvelope(
            version: version,
            rootPath: root?.standardizedFileURL.path,
            entries: Dictionary(uniqueKeysWithValues: entries.map { ($0.key.path, $0.value) })
        )
        save(envelope, at: url)
    }

    static func loadKeyedCacheIfNeeded<Entry: Codable>(
        into cache: inout [String: Entry],
        didLoad: inout Bool,
        at url: URL?,
        version: Int
    ) {
        guard !didLoad else { return }
        didLoad = true
        guard let url,
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheEnvelope<Entry>.self, from: data),
              envelope.version == version else { return }
        cache = envelope.entries
    }

    static func saveKeyedCacheIfChanged<Entry: Codable>(
        _ entries: [String: Entry],
        changed: Bool,
        at url: URL?,
        version: Int
    ) {
        guard changed, let url else { return }
        save(CacheEnvelope(version: version, rootPath: nil, entries: entries), at: url)
    }

    private static func save<Entry: Codable>(_ envelope: CacheEnvelope<Entry>, at url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func saveCacheIfChanged<Entry: Codable>(
        _ entries: [URL: Entry],
        changed: Bool,
        at url: URL?,
        version: Int,
        root: URL? = nil
    ) {
        if changed { saveCache(entries, at: url, version: version, root: root) }
    }

    /// Returns a byte offset only when the cached prefix was fully consumed,
    /// the file grew, and the old boundary ends at a complete JSONL line.
    static func appendOffset(
        currentFileSize: Int,
        cachedFileSize: Int?,
        processedByteCount: Int?,
        file: URL
    ) -> UInt64? {
        guard let cachedFileSize,
              processedByteCount == cachedFileSize,
              currentFileSize > cachedFileSize,
              JSONLReader.isLineBoundary(at: cachedFileSize, in: file) else { return nil }
        return UInt64(cachedFileSize)
    }

    static func fileMetadata(at url: URL) -> (mtime: Date, fileSize: Int)? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = values.contentModificationDate,
              let fileSize = values.fileSize else { return nil }
        return (mtime, fileSize)
    }

    static func enumerator(
        at root: URL,
        errorHandler: ((URL, Error) -> Bool)? = nil
    ) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: errorHandler
        )
    }

    static func modelBuckets(
        from modelByBucketAndModel: [String: TokenTotals],
        platform: TokenPlatform,
        client: TokenClient,
        invalidDatePolicy: InvalidBucketDatePolicy = .omit
    ) -> [TokenUsageBucket] {
        modelByBucketAndModel.compactMap { key, totals in
            let parts = key.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let model = parts[1]
            let bucketStart: Date
            if let date = TokenUsageBucket.date(fromBucketKey: parts[0]) {
                bucketStart = date
            } else {
                switch invalidDatePolicy {
                case .useNow: bucketStart = .now
                case .omit: return nil
                }
            }
            return TokenUsageBucket.modelBucket(
                at: bucketStart, platform: platform, client: client, model: model, totals: totals
            )
        }
    }
}
