import Foundation
import Testing
@testable import QuotaMonitor

struct CacheLiveScanTests {
    @Test func scansConfiguredSourcesWithoutPersistentCaches() async throws {
        guard ProcessInfo.processInfo.environment["QMT_CACHE_LIVE_SCAN"] == "1" else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = CodexEnvironment.homeDirectory
        let claude = home.appendingPathComponent(".claude/projects")
        let workbuddy = home.appendingPathComponent(".workbuddy/traces")
        let clients: [(String, URL, any LocalTokenSnapshotProviding)] = [
            ("Codex", codex, CodexSessionTokenClient(root: codex)),
            ("Claude Code", claude, ClaudeSessionTokenClient(root: claude)),
            ("WorkBuddy", workbuddy, WorkBuddyTraceClient(root: workbuddy))
        ]
        for (name, root, client) in clients {
            guard FileManager.default.fileExists(atPath: root.path) else {
                print("CACHE_LIVE_SCAN \(name): source absent")
                continue
            }
            let snapshot = try await client.fetchSnapshot()
            let eligible = snapshot.buckets.filter { $0.totals.cacheMeasurement != nil }.count
            print("CACHE_LIVE_SCAN \(name): buckets=\(snapshot.buckets.count), eligible=\(eligible)")
        }

        if let harnessSource = LocalToolTokenSource.additional.first(where: { $0.format == .deepseekHarness }) {
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("qmt-live-harness-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: cache) }
            let client = AdditionalLocalTokenClient(sources: [harnessSource], environment: [:], persistentCacheURL: cache)
            let result = try await client.fetchScanResult()
            if let snapshot = result.snapshots.first {
                let measurements = snapshot.buckets.compactMap { $0.totals.cacheMeasurement }
                print("CACHE_LIVE_SCAN DeepSeek Harness: buckets=\(snapshot.buckets.count), eligible=\(measurements.count), cachedInput=\(measurements.reduce(0) { $0 + $1.cachedInput }), eligibleInput=\(measurements.reduce(0) { $0 + $1.input })")
            } else {
                print("CACHE_LIVE_SCAN DeepSeek Harness: source absent")
            }
        }

        if let snapshot = await CCSwitchUsageClient().fetchSnapshot(appType: "claude-desktop") {
            let measurements = snapshot.buckets.compactMap { $0.totals.cacheMeasurement }
            print("CACHE_LIVE_SCAN Claude Desktop: buckets=\(snapshot.buckets.count), eligible=\(measurements.count), cachedInput=\(measurements.reduce(0) { $0 + $1.cachedInput }), eligibleInput=\(measurements.reduce(0) { $0 + $1.input })")
        } else {
            print("CACHE_LIVE_SCAN Claude Desktop: source absent or unreadable")
        }
    }
}
