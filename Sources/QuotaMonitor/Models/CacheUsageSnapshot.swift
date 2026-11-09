import Foundation

/// One pass over the selected period. Hover consumes these values without
/// reading the store or regrouping source buckets.
struct CacheUsageSnapshot {
    let total: CacheUsageSummary?
    let rows: [UsageBreakdownKey: CacheUsageSummary]

    init(buckets: [TokenUsageBucket], freshSources: Set<DataSourceID>,
         platformKeys: Set<UsageBreakdownKey>, modelKeys: Set<UsageBreakdownKey>) {
        var total = Accumulator()
        var groups: [UsageBreakdownKey: Accumulator] = [:]
        for bucket in buckets {
            let measurement = bucket.cacheEvidenceSourceID.flatMap {
                freshSources.contains($0) ? bucket.totals.cacheMeasurement : nil
            }
            total.add(bucket.total, measurement: measurement)
            let platform = UsageBreakdownKey.platformClient(platform: bucket.platform, client: bucket.client)
            let model = UsageBreakdownKey.model(TokenModelName.canonical(bucket.model))
            groups[platformKeys.contains(platform) ? platform : .otherPlatforms, default: Accumulator()]
                .add(bucket.total, measurement: measurement)
            groups[modelKeys.contains(model) ? model : .otherModels, default: Accumulator()]
                .add(bucket.total, measurement: measurement)
        }
        self.total = total.summary
        rows = groups.compactMapValues(\.summary)
    }

    private struct Accumulator {
        var observed = 0
        var measurements: [CacheUsageMeasurement] = []
        var overflow = false

        mutating func add(_ tokens: Int, measurement: CacheUsageMeasurement?) {
            let (next, didOverflow) = observed.addingReportingOverflow(tokens)
            overflow = overflow || didOverflow
            observed = next
            if let measurement { measurements.append(measurement) }
        }

        var summary: CacheUsageSummary? {
            overflow ? nil : CacheUsageSummary(measurements: measurements, observedTokens: observed)
        }
    }
}

extension TokenUsageBucket {
    var cacheEvidenceSourceID: DataSourceID? {
        switch (platform, client) {
        case (.codex, _): DataSourceCatalog.codexToken
        case (.claude, .cli): DataSourceCatalog.claudeCode
        case (.claude, .desktop): DataSourceCatalog.claudeDesktop
        case (.workbuddy, _): DataSourceCatalog.workBuddy
        case (.deepseekHarness, _): LocalToolTokenSource.additional.first { $0.platform == .deepseekHarness }?.dataSourceID
        default: nil
        }
    }
}
