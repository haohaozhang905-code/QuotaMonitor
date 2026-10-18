import CryptoKit
import Foundation
import Testing
@testable import QuotaMonitor

/// 显式启用的本机验收：只读源日志、使用临时缓存，不读取凭据或访问网络。
struct CodexHistoryIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QUOTAMONITOR_VERIFY_CODEX_HISTORY"] == "1"))
    func scansLocalHistoryWithAnIsolatedCache() async throws {
        let root = CodexEnvironment.homeDirectory
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qm-history-acceptance-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compressed = try compressedFiles(in: root)
        let before = try fingerprint(compressed)
        let cache = directory.appendingPathComponent("codex-cache.json")
        let start = Date.now
        let cold = try await CodexSessionTokenClient(root: root, persistentCacheURL: cache).fetchSnapshot()
        let coldSeconds = Date.now.timeIntervalSince(start)
        let reloadStart = Date.now
        let reload = try await CodexSessionTokenClient(root: root, persistentCacheURL: cache).fetchSnapshot()
        let today = Calendar.current.startOfDay(for: .now)
        // 当前会话可能持续追加今日用量，因此只对今日以前的数据做严格相等检查。
        #expect(cold.buckets.filter { $0.bucketStart < today } == reload.buckets.filter { $0.bucketStart < today })
        #expect(try fingerprint(compressed) == before)
        let byMonth = cold.history.reduce(into: [String: Int]()) { totals, day in
            totals[String(day.id.prefix(7)), default: 0] += day.total
        }
        #expect(!cold.history.isEmpty)
        print("LOCAL_HISTORY_ACCEPTANCE compressed_files=\(compressed.count) cold_seconds=\(coldSeconds) reload_seconds=\(Date.now.timeIntervalSince(reloadStart))")
        print("LOCAL_HISTORY_ACCEPTANCE earliest=\(cold.history.map(\.id).min() ?? "none") months=\(byMonth.sorted { $0.key < $1.key })")
        let historicalDaily = cold.history.filter { $0.day < today }.sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.total)" }.joined(separator: "\n")
        print("LOCAL_HISTORY_ACCEPTANCE historical_daily_sha256=\(SHA256.hash(data: Data(historicalDaily.utf8)).description)")
        print("LOCAL_HISTORY_ACCEPTANCE historical_reload_equal=true compressed_source_hashes_and_mtimes_unchanged=true cache=temporary")
    }

    private struct Fingerprint: Equatable {
        let digest: String
        let size: Int
        let modifiedAt: Date?
    }

    private func compressedFiles(in root: URL) throws -> [URL] {
        var files: [URL] = []
        for name in ["sessions", "archived_sessions"] {
            let enumerator = try #require(FileManager.default.enumerator(
                at: root.appendingPathComponent(name), includingPropertiesForKeys: nil
            ))
            for case let file as URL in enumerator where file.lastPathComponent.hasSuffix(".jsonl.zst") {
                files.append(file)
            }
        }
        return files
    }

    private func fingerprint(_ urls: [URL]) throws -> [URL: Fingerprint] {
        var result: [URL: Fingerprint] = [:]
        for url in urls {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var digest = SHA256()
            while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { digest.update(data: bytes) }
            result[url] = Fingerprint(digest: digest.finalize().description, size: values.fileSize ?? -1, modifiedAt: values.contentModificationDate)
        }
        return result
    }
}
