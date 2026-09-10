import CoreGraphics
import Foundation
import Testing
@testable import QuotaMonitor

struct OverviewRiskAndChartTests {
    private let now = Date(timeIntervalSince1970: 1_788_880_000)

    @Test func quotaCoverageUsesRemainingWindowInsteadOfOnlyAbsoluteThresholds() {
        let critical = quotaCandidate(
            metric: .weekly,
            remaining: 0.39,
            resetAfter: 4 * 60 * 60,
            duration: 5 * 60 * 60
        )
        let nearReset = quotaCandidate(
            metric: .session,
            remaining: 0.20,
            resetAfter: 30 * 60,
            duration: 5 * 60 * 60
        )

        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [nearReset, critical], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .critical)
        #expect(result.signal?.metric == .weekly)
        #expect(abs((result.signal?.coverageRatio ?? 0) - 0.4875) < 0.0001)
    }

    @Test func exhaustedQuotaAlwaysWinsEvenWhenResetIsNear() {
        let exhausted = quotaCandidate(
            metric: .session,
            remaining: 0,
            resetAfter: 5 * 60,
            duration: 5 * 60 * 60
        )
        let reminder = quotaCandidate(
            metric: .weekly,
            remaining: 0.45,
            resetAfter: nil,
            duration: nil
        )

        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [reminder, exhausted], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .critical)
        #expect(result.signal?.metric == .session)
        #expect(result.signal?.remainingPercent == 0)
    }

    @Test func simultaneousLowWindowsChooseTheMoreUrgentQuota() {
        let session = quotaCandidate(
            metric: .session,
            remaining: 0.20,
            resetAfter: 4 * 60 * 60,
            duration: 5 * 60 * 60
        )
        let weekly = quotaCandidate(
            metric: .weekly,
            remaining: 0.30,
            resetAfter: 6 * 24 * 60 * 60,
            duration: 7 * 24 * 60 * 60
        )

        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [weekly, session], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .critical)
        #expect(result.signal?.metric == .session)
        #expect(abs((result.signal?.coverageRatio ?? 0) - 0.25) < 0.0001)
    }

    @Test func missingWindowFallsBackToRemainingQuotaThresholds() {
        let critical = quotaCandidate(metric: .weekly, remaining: 0.30, resetAfter: nil, duration: nil)
        let reminder = quotaCandidate(metric: .session, remaining: 0.50, resetAfter: nil, duration: nil)

        let criticalResult = OverviewRiskResolver.resolve(
            input: .init(candidates: [critical], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )
        let reminderResult = OverviewRiskResolver.resolve(
            input: .init(candidates: [reminder], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(criticalResult.level == .critical)
        #expect(criticalResult.signal?.coverageRatio == nil)
        #expect(reminderResult.level == .reminder)
    }

    @Test func sharedBalanceIsOneSignalAndCanOutrankQuota() {
        let balance = OverviewRiskCandidate.balance(amount: 12, estimatedDays: 2)
        let quota = quotaCandidate(metric: .weekly, remaining: 0.45, resetAfter: nil, duration: nil)

        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [quota, balance], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .critical)
        #expect(result.signal?.provider == .deepSeek)
        #expect(result.signal?.metric == .sharedBalance)
        #expect(result.signal?.estimatedDays == 2)
    }

    @Test func partialQuotaFailureDoesNotHideAUsableRiskSignal() {
        let signal = quotaCandidate(metric: .weekly, remaining: 0.45, resetAfter: nil, duration: nil)
        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [signal], unavailableQuotaSourceCount: 1, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .reminder)
        #expect(result.signal != nil)
        #expect(result.unavailableQuotaSourceCount == 1)
        #expect(result.actionPage == .overview)
    }

    @Test func failedQuotaSourceBecomesRecoveryStateWhenNoSignalIsUsable() {
        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [], unavailableQuotaSourceCount: 1, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .trustWarning)
        #expect(result.signal == nil)
        #expect(result.actionPage == .settings)
    }

    @Test func officialClaudeWithoutRealQuotaDoesNotCreateASignal() {
        let result = OverviewRiskResolver.resolve(
            input: .init(candidates: [], unavailableQuotaSourceCount: 0, hasConnectedQuotaRoute: true),
            now: now
        )

        #expect(result.level == .unavailable)
        #expect(result.signal == nil)
        #expect(result.actionPage == .overview)
    }

    @Test func tooltipKeepsTopFiveAndAggregatesTheRest() {
        let entries = (1...7).map {
            ChartTooltipBreakdownEntry(id: "m\($0)", label: "model-\($0)", value: 80 - $0 * 10)
        }
        let compacted = ChartTooltipBreakdown.compact(entries)

        #expect(compacted.count == 6)
        #expect(compacted.prefix(5).map(\.value) == [70, 60, 50, 40, 30])
        #expect(compacted.last?.value == 30)
        #expect(compacted.last?.hiddenItemCount == 2)
        #expect(compacted.reduce(0) { $0 + $1.value } == entries.reduce(0) { $0 + $1.value })
    }

    @Test func stackedGeometryKeepsSegmentsInsideTheComputedBar() {
        let plot = CGRect(x: 44, y: 15, width: 500, height: 123)
        let geometry = StackedBarGeometry.make(
            values: [7_443, 6_062, 4_559, 805, 446, 320, 269, 55, 17, 25],
            peak: 20_001,
            plot: plot,
            barX: 100,
            barWidth: 20,
            hoverX: 94,
            hoverWidth: 32
        )
        let renderedHeight = geometry.segmentRects.reduce(0) { $0 + $1.height }

        #expect(abs(renderedHeight - geometry.barRect.height) < 0.0001)
        #expect(geometry.segmentRects.filter { $0.height > 0 }.allSatisfy {
            $0.minY >= geometry.barRect.minY - 0.0001 && $0.maxY <= geometry.barRect.maxY + 0.0001
        })
        #expect(geometry.hoverRect.minY <= geometry.barRect.minY + 0.0001)
        #expect(geometry.hoverRect.maxY == plot.maxY)
    }

    @Test func shortStackNeverOverflowsWhenEverySegmentNeedsVisibility() {
        let plot = CGRect(x: 0, y: 0, width: 100, height: 10)
        let geometry = StackedBarGeometry.make(
            values: Array(repeating: 1, count: 12),
            peak: 1_000,
            plot: plot,
            barX: 20,
            barWidth: 8,
            hoverX: 18,
            hoverWidth: 12
        )

        #expect(abs(geometry.segmentRects.reduce(0) { $0 + $1.height } - 1) < 0.0001)
        #expect(geometry.barRect.minY >= plot.minY)
        #expect(geometry.barRect.maxY <= plot.maxY)
    }

    @Test func chartPaletteUsesOnlyFiveStableSlots() {
        let values = ["gpt-5.6-sol", "gpt-reserve", "deepseek-v4-flash", "hy3"]
        let firstPass = values.map(UsageBreakdownColor.stableIndex)
        let secondPass = values.map(UsageBreakdownColor.stableIndex)

        #expect(firstPass == secondPass)
        #expect(firstPass.allSatisfy { (0..<5).contains($0) })
        #expect(UsageBreakdownColor.categoryIndex(for: .platformClient(platform: .codex, client: .cli)) == 0)
        #expect(UsageBreakdownColor.categoryIndex(for: .platformClient(platform: .claude, client: .desktop)) == 1)
        #expect(UsageBreakdownColor.categoryIndex(for: .platformClient(platform: .claude, client: .cli)) == 2)
        #expect(UsageBreakdownColor.categoryIndex(for: .platformClient(platform: .workbuddy, client: .desktop)) == 3)
    }

    private func quotaCandidate(
        provider: OverviewRiskProvider = .codex,
        metric: OverviewRiskMetric,
        remaining: Double,
        resetAfter: TimeInterval?,
        duration: TimeInterval?
    ) -> OverviewRiskCandidate {
        .init(
            provider: provider,
            metric: metric,
            remainingPercent: remaining,
            resetsAt: resetAfter.map { now.addingTimeInterval($0) },
            periodDuration: duration,
            balanceAmount: nil,
            estimatedDays: nil
        )
    }
}
