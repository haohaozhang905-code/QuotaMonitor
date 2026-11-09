import AppKit
import SwiftUI
import XCTest
@testable import QuotaMonitor

final class CacheViewRenderTests: XCTestCase {
    @MainActor func testCacheSummaryIncludesDesktopAndHarnessEvidence() throws {
        let store = QuotaStore(tokenSnapshotURL: nil)
        let harness = try XCTUnwrap(LocalToolTokenSource.additional.first { $0.platform == .deepseekHarness })
        store.cacheEvidenceFreshSources = [
            DataSourceCatalog.codexToken,
            DataSourceCatalog.claudeDesktop,
            harness.dataSourceID
        ]
        let fixtures: [(TokenPlatform, TokenClient, String, Int, Int, Int)] = [
            (.codex, .cli, "gpt-6.1-sol", 100, 50, 20),
            (.claude, .desktop, "claude-sonnet", 200, 100, 10),
            (.deepseekHarness, .desktop, "deepseek-v4-flash", 400, 300, 20)
        ]
        let buckets = fixtures.map { platform, client, model, input, cached, output in
            var totals = TokenTotals(input: input, cachedInput: cached, output: output)
            totals.cacheMeasurement = CacheUsageMeasurement(
                input: input, cachedInput: cached, cacheWriteInput: 0, output: output
            )
            return TokenUsageBucket.modelBucket(at: .now, platform: platform, client: client,
                                                model: model, totals: totals)
        }
        let view = MainPanelView(store: store, language: LanguageSettings(), dockIconSettings: DockIconSettings(),
                                 appearanceSettings: AppearanceSettings(), reminderSettings: ReminderSettings())
        let summary = try XCTUnwrap(view.cacheSummary(buckets))
        XCTAssertEqual(summary.eligibleInput, 700)
        XCTAssertEqual(summary.cachedInput, 450)
        XCTAssertEqual(summary.observedTokens, 750)
    }

    @MainActor func testRenderCachePagesWithFixture() throws {
        guard ProcessInfo.processInfo.environment["QMT_CACHE_RENDER"] == "1" else { return }
        let store = QuotaStore(tokenSnapshotURL: nil)
        var totals = TokenTotals(input: 100, cachedInput: 80, output: 100)
        totals.cacheMeasurement = CacheUsageMeasurement(input: 100, cachedInput: 80, cacheWriteInput: nil, output: 100)
        store.tokenBuckets = [.modelBucket(at: .now, platform: .codex, client: .cli, model: "gpt-6.1-sol", totals: totals)]
        store.cacheEvidenceFreshSources = [DataSourceCatalog.codexToken]
        let view = MainPanelView(store: store, language: LanguageSettings(), dockIconSettings: DockIconSettings(), appearanceSettings: AppearanceSettings(), reminderSettings: ReminderSettings())
        for (name, content) in [("overview", AnyView(view.overviewPage)), ("tokens", AnyView(view.tokenPage)),
                                ("overview-small", AnyView(view.overviewPage)), ("tokens-small", AnyView(view.tokenPage))] {
            let width: CGFloat = name.hasSuffix("small") ? 570 : 650
            let renderer = ImageRenderer(content: content.frame(width: width).padding(16).background(Color.white))
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/qmt-cache-\(name).png"))
        }
        let summary = CacheUsageSummary(measurements: [try XCTUnwrap(totals.cacheMeasurement)], observedTokens: 300)
        let detail = CacheInfoDetails(language: LanguageSettings(), summary: summary, scope: "今日", isUpdating: false)
        XCTAssertNotNil(ImageRenderer(content: detail.background(Color.white)).nsImage)
        for (name, value) in [("known", summary), ("unknown", nil)] {
            let tooltip = CacheRateTooltip(name: "Codex", color: PanelTheme.chartPrimary, summary: value, language: LanguageSettings())
            let image = try XCTUnwrap(ImageRenderer(content: tooltip).nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/qmt-ranking-\(name).png"))
        }
    }
}
