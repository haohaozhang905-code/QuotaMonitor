import Foundation
import Testing
@testable import QuotaMonitor

struct DataSourceRuntimeStateTests {
    private let descriptor = DataSourceCatalog.all.first { $0.id == DataSourceCatalog.claudeCode }!
    private let now = Date(timeIntervalSince1970: 1_788_880_000)

    @Test func firstFailureRetainsItsDiagnosticStateWithoutInventingHistory() {
        var source = TokenSourceRuntimeState()
        let attemptedAt = now.addingTimeInterval(1)
        source.begin(at: attemptedAt)
        source.finish(
            with: .failed,
            at: attemptedAt,
            candidateFileCount: nil,
            validRecordCount: 0,
            usesLastGoodData: false
        )

        let snapshot = source.snapshot(for: descriptor, at: now, isInstalled: false)
        #expect(snapshot.state == .failed)
        #expect(snapshot.lastAttemptAt == attemptedAt)
        #expect(snapshot.lastSuccessAt == nil)
        #expect(snapshot.candidateFileCount == 0)
        #expect(snapshot.validRecordCount == 0)
    }

    @Test func failedRefreshRetainsLastGoodCountsAndMarksSourceStale() {
        var source = TokenSourceRuntimeState()
        source.finish(
            with: .ready,
            at: now,
            candidateFileCount: 5,
            validRecordCount: 3,
            usesLastGoodData: false
        )
        source.begin(at: now.addingTimeInterval(60))
        source.finish(
            with: .failed,
            at: now.addingTimeInterval(61),
            candidateFileCount: nil,
            validRecordCount: 0,
            usesLastGoodData: false
        )

        let snapshot = source.snapshot(for: descriptor, at: now.addingTimeInterval(62), isInstalled: true)
        #expect(snapshot.state == .stale)
        #expect(snapshot.usesLastGoodData)
        #expect(snapshot.lastSuccessAt == now)
        #expect(snapshot.candidateFileCount == 5)
        #expect(snapshot.validRecordCount == 3)
    }

    @Test func readySnapshotExpiresUsingTheRegisteredSourceWindow() {
        var source = TokenSourceRuntimeState()
        source.finish(
            with: .ready,
            at: now,
            candidateFileCount: 2,
            validRecordCount: 2,
            usesLastGoodData: false
        )

        let fresh = source.snapshot(for: descriptor, at: now.addingTimeInterval(descriptor.staleAfter), isInstalled: true)
        let expired = source.snapshot(for: descriptor, at: now.addingTimeInterval(descriptor.staleAfter + 1), isInstalled: true)
        #expect(fresh.state == .ready)
        #expect(expired.state == .stale)
        #expect(expired.usesLastGoodData)
    }
}
