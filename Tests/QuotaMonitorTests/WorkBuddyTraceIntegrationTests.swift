import CryptoKit
import Foundation
import Testing
@testable import QuotaMonitor

/// 显式启用的本机验收：只读 WorkBuddy trace，不读取凭据、不访问网络，也不使用正式缓存。
struct WorkBuddyTraceIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QUOTAMONITOR_VERIFY_WORKBUDDY_HISTORY"] == "1"))
    func scansCurrentJSONLHistoryWithoutChangingSources() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".workbuddy", isDirectory: true)
            .appendingPathComponent("traces", isDirectory: true)
        let files = try traceFiles(in: root)
        let jsonlFiles = files.filter { $0.pathExtension.lowercased() == "jsonl" }
        let before = try fingerprint(files)

        let client = WorkBuddyTraceClient(root: root)
        let cold = try await client.fetchSnapshot()
        let reload = try await client.fetchSnapshot()
        let today = Calendar.current.startOfDay(for: .now)
        let recentBoundary = Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today

        #expect(!jsonlFiles.isEmpty)
        #expect(cold.buckets.contains { $0.bucketStart >= recentBoundary })
        #expect(cold.buckets.filter { $0.bucketStart < today } == reload.buckets.filter { $0.bucketStart < today })
        #expect(try fingerprint(files) == before)

        let historicalDaily = cold.history.filter { $0.day < today }.sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.total)" }.joined(separator: "\n")
        let recentDays = cold.history.filter { $0.day >= recentBoundary }.map(\.id).sorted()
        print("WORKBUDDY_HISTORY_ACCEPTANCE files=\(files.count) jsonl_files=\(jsonlFiles.count) earliest=\(cold.history.map(\.id).min() ?? "none") latest=\(cold.history.map(\.id).max() ?? "none") recent_days=\(recentDays)")
        print("WORKBUDDY_HISTORY_ACCEPTANCE historical_daily_sha256=\(SHA256.hash(data: Data(historicalDaily.utf8)).description) reload_equal=true source_hashes_and_mtimes_unchanged=true cache=disabled")
    }

    private struct Fingerprint: Equatable {
        let digest: String
        let size: Int
        let modifiedAt: Date?
    }

    private func traceFiles(in root: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ))
        return enumerator.compactMap { item -> URL? in
            guard let file = item as? URL,
                  file.lastPathComponent.hasPrefix("trace_"),
                  ["json", "jsonl"].contains(file.pathExtension.lowercased()) else { return nil }
            return file
        }
    }

    private func fingerprint(_ urls: [URL]) throws -> [URL: Fingerprint] {
        var result: [URL: Fingerprint] = [:]
        for url in urls {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let file = try FileHandle(forReadingFrom: url)
            var digest = SHA256()
            while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                digest.update(data: bytes)
            }
            try file.close()
            result[url] = Fingerprint(
                digest: digest.finalize().description,
                size: values.fileSize ?? -1,
                modifiedAt: values.contentModificationDate
            )
        }
        return result
    }
}
