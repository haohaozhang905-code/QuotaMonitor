import SwiftUI

extension MainPanelView {
    func cacheBuckets(today: Bool = false) -> [TokenUsageBucket] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        let days = today ? 1 : tokenPeriod.presentationPeriod.fixedDayCount
        let start = days.flatMap { calendar.date(byAdding: .day, value: 1 - $0, to: end) } ?? .distantPast
        let nextDay = calendar.date(byAdding: .day, value: 1, to: end) ?? .distantFuture
        return (store.cacheRefreshSnapshot?.buckets ?? store.tokenBuckets).filter {
            $0.bucketStart >= start && $0.bucketStart < nextDay
        }
    }

    func cacheSummary(_ buckets: [TokenUsageBucket]) -> CacheUsageSummary? {
        let freshSources = store.cacheRefreshSnapshot?.freshSources ?? store.cacheEvidenceFreshSources
        let measurements = buckets.compactMap { bucket -> CacheUsageMeasurement? in
            guard let source = bucket.cacheEvidenceSourceID, freshSources.contains(source) else { return nil }
            return bucket.totals.cacheMeasurement
        }
        return CacheUsageSummary(measurements: measurements, observedTokens: buckets.reduce(0) { $0 + $1.total })
    }

    var cacheHasFailedSources: Bool {
        let harness = LocalToolTokenSource.additional.first { $0.platform == .deepseekHarness }?.dataSourceID
        let tracked = Set([DataSourceCatalog.codexToken, DataSourceCatalog.claudeCode,
                           DataSourceCatalog.claudeDesktop, DataSourceCatalog.workBuddy] + [harness].compactMap { $0 })
        return store.dataSourceHealth.contains {
            tracked.contains($0.id) && $0.isInstalled && $0.lastAttemptAt != nil &&
                ($0.state == .failed || $0.state == .stale || $0.state == .needsPermission)
        }
    }

}

struct CacheInfoButton: View {
    let language: LanguageSettings
    let summary: CacheUsageSummary?
    let scope: String
    let isUpdating: Bool
    var hasFailedSources = false
    @State private var showing = false

    var body: some View {
        PanelHelpButton(
            isPresented: $showing,
            width: 250,
            arrowEdge: .trailing,
            accessibilityLabel: scope + ", " + language.text("cache.help") + ((summary?.isPartial == true || hasFailedSources) ? ", " + language.text("cache.partial") : "")
        ) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(PanelTheme.text2)
        } content: {
            CacheInfoDetails(language: language, summary: summary, scope: scope,
                             isUpdating: isUpdating, hasFailedSources: hasFailedSources)
        }
    }
}

struct CacheInfoDetails: View {
    let language: LanguageSettings
    let summary: CacheUsageSummary?
    let scope: String
    let isUpdating: Bool
    var hasFailedSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("cache.brief.title"))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(language.text("cache.brief.definition"))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if isUpdating {
                Text(language.text(summary?.hitRate == nil ? "cache.loading" : "cache.updating"))
                    .foregroundStyle(.primary)
            } else if summary?.hitRate == nil {
                Text(language.text("cache.unavailable"))
                    .foregroundStyle(.primary)
            } else if summary?.isPartial == true || hasFailedSources {
                Text(language.text("cache.brief.partial"))
                    .foregroundStyle(.primary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CacheRowTooltipAnchor {
    let name: String
    let color: Color
    let summary: CacheUsageSummary?
    let bounds: Anchor<CGRect>
}
struct CacheRowTooltipPreference: PreferenceKey {
    static let defaultValue: CacheRowTooltipAnchor? = nil
    static func reduce(value: inout CacheRowTooltipAnchor?, nextValue: () -> CacheRowTooltipAnchor?) {
        if let next = nextValue() { value = next }
    }
}
struct CacheRowInspection: ViewModifier {
    let id: String
    let name: String
    let color: Color
    let summary: CacheUsageSummary?
    let language: LanguageSettings
    let value: Int
    let share: Double
    let selection: String?
    let onHoverChange: (String, Bool) -> Void
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .opacity(selection == nil || selection == id ? 1 : 0.42)
            .onHover { active in
                onHoverChange(id, active)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(language.text("cache.row.accessibility", QuotaFormatters.localizedTokens(value, language: language.language), String(format: "%.1f%%", share * 100), CacheUsageSummary.percentage(summary?.hitRate)))
            .anchorPreference(key: CacheRowTooltipPreference.self, value: .bounds) { bounds in
                selection == id ? CacheRowTooltipAnchor(name: name, color: color, summary: summary, bounds: bounds) : nil
            }
    }
}
struct CacheRateTooltip: View {
    let name: String
    let color: Color
    let summary: CacheUsageSummary?
    let language: LanguageSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(language.text("cache.rate"))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelTheme.text2).lineLimit(1)
                Spacer(minLength: 6)
                Text(CacheUsageSummary.percentage(summary?.hitRate))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
            }
            Rectangle().fill(PanelTheme.separator).frame(height: 1)
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(PanelTheme.text2)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(summary?.hitRate == nil ? "—/—" : "\(QuotaFormatters.localizedTokens(summary?.cachedInput ?? 0, language: language.language))/\(QuotaFormatters.localizedTokens(summary?.eligibleInput ?? 0, language: language.language))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(PanelTheme.text).fixedSize()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(width: 220)
        .background(PanelTheme.tooltipSurface, in: RoundedRectangle(cornerRadius: PanelTheme.tooltipCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PanelTheme.tooltipCornerRadius, style: .continuous).stroke(PanelTheme.tooltipBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// This local state prevents mouse movement from invalidating the dashboard's
/// data preparation, chart snapshots, heatmap and period cache summaries.
struct CacheRankingInteraction<Content: View>: View {
    let language: LanguageSettings
    @ViewBuilder let content: (String?, @escaping (String, Bool) -> Void) -> Content
    @State private var hoveredUsageRow: String?
    @State private var usageHoverClearTask: Task<Void, Never>?

    var body: some View {
        content(hoveredUsageRow, updateUsageRowHover)
            .overlayPreferenceValue(CacheRowTooltipPreference.self) { selection in
                GeometryReader { proxy in
                    if let selection {
                        let rect = proxy[selection.bounds]
                        CacheRateTooltip(name: selection.name, color: selection.color, summary: selection.summary, language: language)
                            .fixedSize(horizontal: false, vertical: true)
                            .position(x: min(max(rect.midX, 120), max(proxy.size.width - 120, 120)), y: rect.minY - 44)
                    }
                }
                .allowsHitTesting(false)
            }
            .onDisappear { resetUsageRowHover() }
    }

    private func updateUsageRowHover(_ id: String, isHovering: Bool) {
        usageHoverClearTask?.cancel()
        usageHoverClearTask = nil
        if isHovering {
            hoveredUsageRow = id
        } else {
            usageHoverClearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, hoveredUsageRow == id else { return }
                hoveredUsageRow = nil
                usageHoverClearTask = nil
            }
        }
    }

    private func resetUsageRowHover() {
        usageHoverClearTask?.cancel()
        usageHoverClearTask = nil
        hoveredUsageRow = nil
    }

}
