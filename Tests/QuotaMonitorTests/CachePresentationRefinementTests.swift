import Foundation
import Testing
@testable import QuotaMonitor

struct CachePresentationRefinementTests {
    private func bucket(platform: TokenPlatform = .codex, model: String, input: Int, cached: Int?, output: Int) -> TokenUsageBucket {
        var totals = TokenTotals(input: input, cachedInput: cached ?? 0, output: output)
        totals.cacheMeasurement = CacheUsageMeasurement(input: input, cachedInput: cached, cacheWriteInput: nil, output: output)
        return .modelBucket(at: .now, platform: platform, client: .cli, model: model, totals: totals)
    }

    @Test func groupedSummariesMatchWeightedTotalsAndOtherModels() throws {
        let buckets = [bucket(model: "alpha", input: 100, cached: 80, output: 50),
                       bucket(model: "alpha", input: 300, cached: 240, output: 100),
                       bucket(model: "beta", input: 50, cached: 10, output: 20),
                       bucket(model: "unknown", input: 100, cached: nil, output: 30)]
        let platform = UsageBreakdownKey.platformClient(platform: .codex, client: .cli)
        let snapshot = CacheUsageSnapshot(buckets: buckets, freshSources: [DataSourceCatalog.codexToken],
                                          platformKeys: [platform], modelKeys: [.model("alpha"), .otherModels])
        #expect(snapshot.total?.observedTokens == 750)
        #expect(snapshot.total?.eligibleInput == 450)
        #expect(snapshot.total?.cachedInput == 330)
        #expect(snapshot.total == snapshot.rows[platform])
        #expect(snapshot.rows[.model("alpha")]?.hitRate == 0.8)
        #expect(snapshot.rows[.otherModels]?.observedTokens == 200)
        #expect(snapshot.rows[.otherModels]?.eligibleInput == 50)
        #expect(snapshot.rows[.otherModels]?.isPartial == true)
    }

    @Test func staleEvidenceAndUnsupportedSourcesKeepObservedUsageWithoutInventingZeroHits() {
        let buckets = [bucket(model: "alpha", input: 100, cached: 80, output: 50),
                       bucket(platform: .workbuddy, model: "beta", input: 200, cached: 100, output: 30)]
        let snapshot = CacheUsageSnapshot(buckets: buckets, freshSources: [DataSourceCatalog.workBuddy],
                                          platformKeys: [], modelKeys: [.model("alpha")])
        #expect(snapshot.total?.observedTokens == 380)
        #expect(snapshot.total?.eligibleInput == 200)
        #expect(snapshot.total?.cachedInput == 100)
        #expect(snapshot.rows[.model("alpha")]?.hitRate == nil)
        #expect(snapshot.rows[.model("alpha")]?.observedTokens == 150)
        #expect(snapshot.rows[.otherPlatforms] == snapshot.total)
    }

    @Test func largePeriodGroupingMatchesReferenceFiltering() {
        let buckets = (0..<20_000).map { index in
            bucket(model: index % 2 == 0 ? "alpha" : "beta", input: 100, cached: index % 3 == 0 ? nil : 80, output: 20)
        }
        let start = ContinuousClock.now
        let snapshot = CacheUsageSnapshot(buckets: buckets, freshSources: [DataSourceCatalog.codexToken],
                                          platformKeys: [], modelKeys: [.model("alpha"), .otherModels])
        let elapsed = start.duration(to: .now)
        for (key, model) in [(UsageBreakdownKey.model("alpha"), "alpha"), (.otherModels, "beta")] {
            let filtered = buckets.filter { TokenModelName.canonical($0.model) == model }
            let reference = CacheUsageSummary(measurements: filtered.compactMap { $0.totals.cacheMeasurement },
                                              observedTokens: filtered.reduce(0) { $0 + $1.total })
            #expect(snapshot.rows[key] == reference)
        }
        if ProcessInfo.processInfo.environment["QMT_CACHE_BENCHMARK"] == "1" {
            print("Cache period grouping: 20,000 buckets, \(elapsed)")
        }
    }

    @Test func capabilityStatesSeparateNeutralWarningsAndFailures() {
        #expect(SourceCapabilityPresentation(states: []) == .notProvided)
        #expect(SourceCapabilityPresentation(states: [.noData]) == .noData)
        #expect(SourceCapabilityPresentation(states: [.scanning, .noData]) == .scanning)
        #expect(SourceCapabilityPresentation(states: [.failed, .ready]) == .ready)
        #expect(SourceCapabilityPresentation(states: [.stale, .noData]) == .stale)
        #expect(SourceCapabilityPresentation(states: [.failed, .scanning]) == .failed)
        #expect(SourceCapabilityPresentation(states: [.needsPermission]) == .needsPermission)
        #expect(SourceCapabilityPresentation(states: [.unsupportedFormat]) == .unsupportedFormat)
    }
}
