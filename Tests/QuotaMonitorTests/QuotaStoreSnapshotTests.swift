import Foundation
import Testing
@testable import QuotaMonitor

struct QuotaStoreSnapshotTests {
    private struct LegacySnapshotV2: Codable {
        let version: Int
        let tokenHistory: [DailyTokenUsage]
        let claudeHistory: [DailyTokenUsage]
        let claudeDesktopHistory: [DailyTokenUsage]
        let workBuddyHistory: [DailyTokenUsage]
        let codexDeepSeekHistory: [DailyTokenUsage]
        let claudeDeepSeekHistory: [DailyTokenUsage]
        let desktopDeepSeekHistory: [DailyTokenUsage]
        let workbuddyDeepSeekHistory: [DailyTokenUsage]
        let tokenBuckets: [TokenUsageBucket]
        let claudeDesktopStale: Bool
        let tokenUpdatedAt: Date?
    }

    @MainActor
    @Test func successfulCodexRefreshClearsResetCreditsMissingFromTheNewSnapshot() {
        let store = QuotaStore(tokenSnapshotURL: nil)
        let firstFetch = Date(timeIntervalSince1970: 1_789_200_000)
        let firstProvider = ProviderUsage(
            providerId: "codex",
            displayName: "Codex",
            plan: nil,
            lines: [],
            fetchedAt: firstFetch
        )
        let previousCredits = CodexResetCredits(
            availableCount: 2,
            expirations: [firstFetch.addingTimeInterval(60 * 60)],
            fetchedAt: firstFetch
        )

        store.applyDirectCodex(CodexDirectSnapshot(provider: firstProvider, resetCredits: previousCredits))
        #expect(store.codexResetCredits == previousCredits)

        let nextFetch = firstFetch.addingTimeInterval(1)
        let nextProvider = ProviderUsage(
            providerId: "codex",
            displayName: "Codex",
            plan: nil,
            lines: [],
            fetchedAt: nextFetch
        )
        store.applyDirectCodex(CodexDirectSnapshot(provider: nextProvider, resetCredits: nil))

        #expect(store.codexResetCredits == nil)
    }

    @Test @MainActor func versionTwoSnapshotLoadsBucketsAndRestoresSourceHealth() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaMonitorSnapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshotURL = directory.appendingPathComponent("token-history-snapshot-v2.json")

        let updatedAt = Date(timeIntervalSince1970: 1_789_200_000)
        let day = Calendar.current.startOfDay(for: updatedAt)
        let codexUsage = DailyTokenUsage(day: day, input: 120, cachedInput: 20, cacheWriteInput: 0, output: 30, reasoning: 5)
        let codexBucket = TokenUsageBucket(
            bucketStart: updatedAt,
            platform: .codex,
            client: .cli,
            model: "gpt-5.6-sol",
            provider: .official,
            totals: TokenTotals(input: 120, cachedInput: 20, output: 30, reasoning: 5)
        )
        let desktopBucket = TokenUsageBucket(
            bucketStart: updatedAt,
            platform: .claude,
            client: .desktop,
            model: "claude-sonnet",
            provider: .official,
            totals: TokenTotals(input: 40, output: 10)
        )
        let legacy = LegacySnapshotV2(
            version: 2,
            tokenHistory: [codexUsage],
            claudeHistory: [],
            claudeDesktopHistory: [],
            workBuddyHistory: [],
            codexDeepSeekHistory: [],
            claudeDeepSeekHistory: [],
            desktopDeepSeekHistory: [],
            workbuddyDeepSeekHistory: [],
            tokenBuckets: [codexBucket, desktopBucket],
            claudeDesktopStale: true,
            tokenUpdatedAt: updatedAt
        )
        try JSONEncoder().encode(legacy).write(to: snapshotURL)

        let store = QuotaStore(tokenSnapshotURL: snapshotURL)
        #expect(Set(store.tokenBuckets.map(\.id)) == Set([codexBucket, desktopBucket].map(\.id)))
        #expect(store.tokenHistory.first?.total == codexUsage.total)
        #expect(store.lastTokenUpdatedAt == updatedAt)

        let health = store.dataSourceHealth(at: updatedAt)
        #expect(health.first { $0.id == DataSourceCatalog.codexToken }?.state == .ready)
        #expect(health.first { $0.id == DataSourceCatalog.claudeDesktop }?.state == .stale)
        #expect(health.first { $0.id == DataSourceCatalog.claudeDesktop }?.usesLastGoodData == true)
    }
}

struct TokenRefreshWakeupStateTests {
    @Test func repeatedFileEventsKeepTheFirstRefreshDeadline() {
        var state = TokenRefreshWakeupState()

        let first = state.requestRefresh(isScanning: false)
        let second = state.requestRefresh(isScanning: false)
        let third = state.requestRefresh(isScanning: false)
        #expect(first)
        #expect(!second)
        #expect(!third)
        #expect(state.isDebounceScheduled)
        let shouldRefresh = state.debounceDidFire(isScanning: false)
        #expect(shouldRefresh)
    }

    @Test func fileEventsDuringAScanRequestOneFollowUpWithoutCancellingTheScan() {
        var state = TokenRefreshWakeupState()

        let first = state.requestRefresh(isScanning: true)
        let second = state.requestRefresh(isScanning: true)
        #expect(!first)
        #expect(!second)
        #expect(state.needsRefreshAfterCurrentScan)
        let shouldScheduleFollowUp = state.scanDidFinish()
        #expect(shouldScheduleFollowUp)
        #expect(state.isDebounceScheduled)
        #expect(!state.needsRefreshAfterCurrentScan)
    }

    @Test func debounceFiringDuringAnotherRefreshIsRetriedAfterThatRefresh() {
        var state = TokenRefreshWakeupState()

        let scheduled = state.requestRefresh(isScanning: false)
        let firedWhileScanning = state.debounceDidFire(isScanning: true)
        #expect(scheduled)
        #expect(!firedWhileScanning)
        #expect(state.needsRefreshAfterCurrentScan)
        let shouldScheduleFollowUp = state.scanDidFinish()
        #expect(shouldScheduleFollowUp)
        #expect(state.isDebounceScheduled)
    }
}
