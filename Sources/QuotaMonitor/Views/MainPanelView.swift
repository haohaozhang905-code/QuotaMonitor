import AppKit
import SwiftUI

extension Notification.Name {
    static let quotaMonitorOpenSettings = Notification.Name("QuotaMonitor.openSettings")
    static let quotaMonitorToggleZoom = Notification.Name("QuotaMonitor.toggleZoom")
}

// MARK: - 余额状态

enum BalanceState {
    case normal
    case low
    case critical
    case unknown

    /// 百分比卡阈值：≤10% 危急，≤50% 低余额。
    init(remainingPercent: Double?) {
        guard let remaining = remainingPercent else { self = .unknown; return }
        if remaining <= 0.10 { self = .critical }
        else if remaining <= 0.50 { self = .low }
        else { self = .normal }
    }

    /// 余额卡阈值：≤2 天危急，≤7 天低余额。
    init(days: Int?) {
        guard let days else { self = .unknown; return }
        if days <= 2 { self = .critical }
        else if days <= 7 { self = .low }
        else { self = .normal }
    }

    var color: Color {
        switch self {
        case .normal: PanelTheme.codex
        case .low: PanelTheme.warn
        case .critical: PanelTheme.danger
        case .unknown: PanelTheme.text2
        }
    }

    var isAlert: Bool {
        switch self {
        case .low, .critical: true
        case .normal, .unknown: false
        }
    }
}

enum MainPanelLayout {
    static let sidebarWidth: CGFloat = 210
    static let sidebarLeadingInset: CGFloat = 16
}

private enum DashboardPage: String, CaseIterable {
    case overview
    case tokens
    case settings

    var titleKey: String {
        switch self {
        case .overview: "panel.overviewTitle"
        case .tokens: "panel.tokensTab"
        case .settings: "settings.title"
        }
    }

    var iconName: String {
        switch self {
        case .overview: "house"
        case .tokens: "chart.bar"
        case .settings: "slider.horizontal.3"
        }
    }
}

private enum TokenPeriod: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case all

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .all: 365
        }
    }

    var fixedDayCount: Int? {
        self == .all ? nil : dayCount
    }

    var localizationKey: String {
        switch self {
        case .sevenDays: "panel.tokenPeriod.sevenDays"
        case .thirtyDays: "panel.tokenPeriod.thirtyDays"
        case .ninetyDays: "panel.tokenPeriod.ninetyDays"
        case .all: "panel.tokenPeriod.all"
        }
    }

    var presentationPeriod: TokenDashboardPeriod {
        switch self {
        case .sevenDays: .sevenDays
        case .thirtyDays: .thirtyDays
        case .ninetyDays: .ninetyDays
        case .all: .all
        }
    }
}

private enum TokenChartDimension: String, CaseIterable, Identifiable {
    case platform
    case model

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .platform: "panel.tokenDimension.platform"
        case .model: "panel.tokenDimension.model"
        }
    }
}

// MARK: - 主面板

struct MainPanelView: View {
    let store: QuotaStore
    @Bindable var language: LanguageSettings
    @Bindable var dockIconSettings: DockIconSettings
    @State private var loginItem = LoginItemManager()
    @State private var selectedPage: DashboardPage = .overview
    @State private var tokenPeriod: TokenPeriod = .sevenDays
    @State private var tokenChartDimension: TokenChartDimension = .platform
    @State private var hoveredPage: DashboardPage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                titlebar
                if shouldShowEmptyState {
                    emptyState
                } else {
                    panelBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PanelTheme.background)
        .frame(minWidth: 820, minHeight: 540)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .quotaMonitorOpenSettings)) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                selectedPage = .settings
            }
        }
    }

    private var titlebar: some View {
        ZStack {
            Text(QuotaMonitorIdentity.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(PanelTheme.text2)
                // 标题栏属于右侧内容列，但标题视觉中心要落在整个窗口中心。
                .offset(x: -MainPanelLayout.sidebarWidth / 2, y: -2)
            HStack {
                Spacer()
                TitlebarStatusView(store: store, language: language)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 38)
        .background(PanelTheme.background.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PanelTheme.separator)
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NotificationCenter.default.post(name: .quotaMonitorToggleZoom, object: nil)
        }
    }

    private var panelBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let message = store.errorMessageKey.map({ language.text($0) }) {
                    errorBanner(message: message)
                }
                pageContent
                    .id(selectedPage)
                    .transition(pageTransition)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        // 保留滚动能力，但不显示系统滚动条；主面板的内容边界由卡片和留白表达。
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shouldShowEmptyState: Bool {
        switch store.presentationSnapshot.availability {
        case .loading, .unavailable, .error: true
        case .ready, .connectedOnly, .stale: false
        }
    }

    private static let applicationIcon: NSImage = {
        let source = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let target = NSImage(size: NSSize(width: 64, height: 64))
        let highResolutionRepresentation = source.representations
            .filter { $0.pixelsWide >= 128 && $0.pixelsHigh >= 128 }
            .min { lhs, rhs in
                abs(lhs.pixelsWide - 128) < abs(rhs.pixelsWide - 128)
            }
        if let highResolutionRepresentation {
            // 侧边栏现在是 64pt，需要至少 128px 的 2x 图层，避免把 32pt 图层插值放大。
            target.addRepresentation(highResolutionRepresentation)
        }
        return target.representations.isEmpty ? source : target
    }()

    private var pageTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(x: 5))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 38)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                // 直接使用 Finder/Dock 为应用包返回的图标；侧边栏品牌图标按 64pt 展示。
                Image(nsImage: Self.applicationIcon)
                    .interpolation(.high)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                Text(QuotaMonitorIdentity.displayName)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
            }
            .padding(.horizontal, MainPanelLayout.sidebarLeadingInset)
            .padding(.top, 10)
            .padding(.bottom, 14)

            VStack(spacing: 3) {
                ForEach(DashboardPage.allCases, id: \.self) { page in
                    Button {
                        guard selectedPage != page else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            selectedPage = page
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.iconName)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 15)
                            Text(language.text(page.titleKey))
                                .font(.system(size: 12, weight: selectedPage == page ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedPage == page ? PanelTheme.codexDeep : PanelTheme.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            selectedPage == page
                                ? PanelTheme.codexSoft
                                : (hoveredPage == page ? Color.primary.opacity(0.07) : .clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredPage = hovering ? page : (hoveredPage == page ? nil : hoveredPage)
                    }
                }
            }
            .padding(.horizontal, 9)

            Spacer(minLength: 0)
        }
        .frame(width: MainPanelLayout.sidebarWidth)
        .background(PanelTheme.sidebar)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .overview:
            overviewPage
        case .tokens:
            tokenPage
        case .settings:
            settingsPage
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewHeading
            overviewHeroCard
            overviewQuotaGrid
            overviewBottomGrid
        }
    }

    private var overviewHeading: some View {
        Text(language.text("overview.pageTitle"))
            .font(.system(size: 22, weight: .bold))
            .kerning(-0.4)
            .foregroundStyle(PanelTheme.text)
    }

    /// 首页首卡只回答三个问题：今天用了多少、和昨天比如何、近 7 天的量级。
    private var overviewHeroCard: some View {
        let presentation = store.presentationSnapshot
        return panelCard {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text("menu.todayTokensLabel"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PanelTheme.text3)
                    Text(QuotaFormatters.localizedTokens(presentation.today.total, language: language.language))
                        .font(.system(size: 34, weight: .bold))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text)
                    Text(heroSubtext)
                        .font(.system(size: 11, weight: .regular))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text2)
                }
                if let delta = relativeDeltaText {
                    Text(delta)
                        .font(.system(size: 10, weight: .medium))
                        .fontDesign(.monospaced)
                        .foregroundStyle(relativeDeltaColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(relativeDeltaColor.opacity(0.14), in: Capsule())
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                overviewHeroMetric(language.text("overview.last7Total"), QuotaFormatters.localizedTokens(presentation.lastSevenDays.total, language: language.language))
                overviewHeroMetric(language.text("overview.todayPeakShare"), todayPeakShare)
                overviewHeroMetric(
                    language.text("overview.leadingModel"),
                    presentation.modelToday.first?.key.displayName() ?? "--"
                )
            }
            .padding(.top, 7)
        }
    }

    private var heroSubtext: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let updated = store.lastUpdated.map { formatter.string(from: $0) } ?? "--:--"
        let yesterday = store.yesterdayTokenUsage.map { QuotaFormatters.localizedTokens($0.total, language: language.language) } ?? "--"
        return language.text("overview.yesterdayUpdated", yesterday, updated)
    }

    private var todayPeakShare: String {
        let total = max(store.presentationSnapshot.lastSevenDays.total, 1)
        return String(format: "%.1f%%", Double(store.presentationSnapshot.today.total) / Double(total) * 100)
    }

    private func overviewHeroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PanelTheme.text3)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relativeDeltaText: String? {
        guard let today = store.todayTokenUsage?.total,
              let yesterday = store.yesterdayTokenUsage?.total,
              let percent = DailyTokenUsage.trendPercent(today: today, yesterday: yesterday) else { return nil }
        let key = percent >= 0 ? "menu.vsYesterdayUp" : "menu.vsYesterdayDown"
        return language.text(key, String(format: "%.1f", abs(percent)))
    }

    private var relativeDeltaColor: Color {
        guard let today = store.todayTokenUsage?.total,
              let yesterday = store.yesterdayTokenUsage?.total else { return PanelTheme.text2 }
        return today >= yesterday ? PanelTheme.claude : PanelTheme.ok
    }

    private var overviewQuotaGrid: some View {
        Group {
            if overviewQuotaItems.isEmpty {
                panelCard(height: 76) {
                    Text(language.text("overview.noQuotaSources"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PanelTheme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(overviewQuotaItems) { item in
                        overviewQuotaCard(
                            icon: item.icon,
                            name: item.name,
                            route: item.route,
                            facts: item.facts,
                            state: item.state
                        )
                    }
                }
            }
        }
    }

    private var overviewQuotaItems: [OverviewQuotaItem] {
        var items: [OverviewQuotaItem] = []
        if store.codexRoute != .unknown {
            items.append(.init(
                platform: .codex,
                icon: .codex,
                name: TokenPlatform.codex.displayName,
                route: codexOverviewRoute,
                facts: codexOverviewFacts,
                state: codexOverviewState
            ))
        }
        if store.claudeDisplayRoute != .unknown {
            items.append(.init(
                platform: .claude,
                icon: .claude,
                name: TokenPlatform.claude.displayName,
                route: claudeOverviewRoute,
                facts: claudeOverviewFacts,
                state: claudeOverviewState
            ))
        }
        return items
    }

    private struct OverviewQuotaItem: Identifiable {
        let platform: TokenPlatform
        let icon: BrandIconKind
        let name: String
        let route: String
        let facts: [(String, String, String)]
        let state: BalanceState?

        var id: String { platform.rawValue }
    }

    private var codexOverviewRoute: String {
        switch store.codexRoute {
        case .deepseek: language.text("panel.deepSeekRouteTag")
        case .official: codexProvider?.plan ?? language.text("panel.official")
        case .unknown: language.text("settings.notConnected")
        }
    }

    private var claudeOverviewRoute: String {
        switch store.claudeDisplayRoute {
        case .deepseek: language.text("panel.deepSeekRouteTag")
        case .official: "Pro"
        case .other: language.text("panel.routeOther")
        case .mixed: language.text("panel.routeMixed")
        case .unknown: language.text("settings.notConnected")
        }
    }

    private var codexOverviewFacts: [(String, String, String)] {
        if QuotaPresentationPolicy.mode(for: store.codexRoute) == .sharedBalance { return sharedOverviewFacts }
        return [
            (language.text("panel.sessionLeft"), codexProvider?.session?.remainingPercent.map(QuotaFormatters.percent) ?? "--", codexResetText(codexProvider?.session)),
            (language.text("overview.weekQuota"), codexProvider?.weekly?.remainingPercent.map(QuotaFormatters.percent) ?? "--", codexResetText(codexProvider?.weekly))
        ]
    }

    private var claudeOverviewFacts: [(String, String, String)] {
        if store.claudeUsesDeepSeek { return sharedOverviewFacts }
        let detail = store.claudeRouteSummary == .unknown
            ? language.text("settings.notConnected")
            : language.text("overview.quotaUnavailable")
        return [
            (language.text("overview.sessionQuota"), "--", detail),
            (language.text("overview.weekQuota"), "--", detail)
        ]
    }

    private var sharedOverviewFacts: [(String, String, String)] {
        [
            (language.text("overview.sharedBalance"), sharedBalanceText, language.text("overview.balanceNoReset")),
            (language.text("overview.estimatedDays"), store.deepSeekDays.map { language.text("panel.daysShortLabel", "\($0)") } ?? "--", language.text("overview.estimateNote"))
        ]
    }

    private var codexOverviewState: BalanceState? {
        switch store.codexRoute {
        case .deepseek: BalanceState(days: store.deepSeekDays)
        case .official: BalanceState(remainingPercent: codexProvider?.weekly?.remainingPercent)
        case .unknown: nil
        }
    }

    private var claudeOverviewState: BalanceState? {
        if store.claudeUsesDeepSeek { return BalanceState(days: store.deepSeekDays) }
        return switch store.claudeRouteSummary {
        case .official, .other, .mixed: BalanceState.unknown
        case .deepseek: BalanceState(days: store.deepSeekDays)
        case .unknown: nil
        }
    }

    private func codexResetText(_ line: UsageLine?) -> String {
        guard let line else { return language.text("overview.noResetData") }
        guard let reset = line.resetsAt else { return language.text("overview.noResetData") }
        return language.text("overview.resetAfter", QuotaFormatters.reset(language: language.language).string(from: reset))
    }

    private func overviewQuotaCard(
        icon: BrandIconKind,
        name: String,
        route: String,
        facts: [(String, String, String)],
        state: BalanceState?
    ) -> some View {
        let status = overviewStatus(for: state)
        return panelCard {
            HStack(spacing: 8) {
                BrandIconView(kind: icon, size: icon == .codex ? 22 : 18)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelTheme.text)
                    Text(route)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(PanelTheme.text3)
                }
                Spacer(minLength: 8)
                Text(status.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(status.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.0)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(PanelTheme.text3)
                        Text(fact.1)
                            .font(.system(size: 20, weight: .semibold))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(fact.2)
                            .font(.system(size: 9, weight: .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    if index == 0 {
                        Rectangle()
                            .fill(PanelTheme.separator)
                            .frame(width: 1, height: 57)
                            .padding(.horizontal, 13)
                    }
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(PanelTheme.separator).frame(height: 0.5).padding(.top, 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewBottomGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewHourlyTokenCard
            HStack(alignment: .top, spacing: 14) {
                overviewListCard(title: language.text("overview.platform"), values: platformSummaries)
                overviewListCard(title: language.text("overview.model"), values: modelSummaries)
            }
        }
    }

    private func overviewStatus(for state: BalanceState?) -> (label: String, color: Color, background: Color) {
        guard let state else {
            return (language.text("settings.notConnected"), PanelTheme.text2, PanelTheme.surface2)
        }
        switch state {
        case .normal:
            return (language.text("overview.healthy"), PanelTheme.ok, PanelTheme.okSoft)
        case .low:
            return (language.text("overview.low"), PanelTheme.warn, PanelTheme.warnSoft)
        case .critical:
            return (language.text("overview.critical"), PanelTheme.danger, PanelTheme.dangerSoft)
        case .unknown:
            return (language.text("overview.quotaUnavailable"), PanelTheme.text2, PanelTheme.surface2)
        }
    }

    private var overviewHourlyTokenCard: some View {
        let chart = hourlyTokenChartSnapshot()
        let axisIndices = hourlyChartAxisIndices
        // Let the card size itself from the plot and tick labels so
        // the bottom axis is never clipped by a fixed outer height.
        return panelCard {
            HStack {
                Text(language.text("overview.todayHourlyTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("overview.todayHourlyNote"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(PanelTheme.text3)
            }
            StackedBarChart(
                rows: chart.rows,
                todayLabel: language.text("panel.today"),
                tokenLabel: language.text("panel.totalTokens"),
                language: language.language
            )
                .frame(height: 92)
                .padding(.top, 4)
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 44, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(axisIndices, id: \.self) { index in
                        let row = chart.rows[index]
                        let x = 40 + (CGFloat(index) + 0.5) / CGFloat(max(chart.rows.count, 1)) * plotWidth
                        Text(row.label)
                            .font(.system(size: 8, weight: .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .fixedSize()
                            .position(x: x, y: 5)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    private var platformSummaries: [BreakdownItem] {
        store.presentationSnapshot.topPlatforms(limit: 4).map { row in
            BreakdownItem(
                name: row.key.displayName(
                    claudeCode: language.text("panel.claudeCode"),
                    other: language.text("tokens.otherPlatform")
                ),
                value: row.total,
                share: row.share,
                color: breakdownColor(for: row.key)
            )
        }
    }

    private var modelSummaries: [BreakdownItem] {
        let rows = store.presentationSnapshot.topModels(limit: 4)
        let colors = modelColors(for: rows)
        return rows.map { row in
            BreakdownItem(
                name: row.key.displayName(other: language.text("tokens.otherModel")),
                value: row.total,
                share: row.share,
                color: colors[row.id] ?? PanelTheme.modelFallback
            )
        }
    }

    private func modelColors(for rows: [UsageBreakdownSnapshot]) -> [String: Color] {
        let categories = rows.map { row in
            TokenChartCategory(
                id: row.id,
                name: row.key.displayName(),
                preferredPaletteIndex: stablePaletteIndex(for: row.id)
            )
        }
        return categoryColors(for: categories)
    }

    private func breakdownColor(for key: UsageBreakdownKey) -> Color {
        switch key {
        case let .platformClient(platform, client):
            switch (platform, client) {
            case (.codex, _): PanelTheme.codex
            case (.claude, .cli): PanelTheme.claudeCode
            case (.claude, _): PanelTheme.claude
            case (.workbuddy, _): PanelTheme.workbuddy
            default: stableCategoryColor(for: platform.rawValue)
            }
        case let .model(model): stableCategoryColor(for: model)
        case .otherModels, .otherPlatforms: PanelTheme.modelFallback
        }
    }

    private func breakdownItems(_ values: [(String, Int, Color)]) -> [BreakdownItem] {
        let total = values.reduce(0) { $0 + $1.1 }
        return values.filter { $0.1 > 0 }.map { BreakdownItem(name: $0.0, value: $0.1, share: total > 0 ? Double($0.1) / Double(total) : 0, color: $0.2) }
    }

    private func overviewListCard(title: String, values: [BreakdownItem]) -> some View {
        let rowHeight: CGFloat = 17
        let rowSpacing: CGFloat = 5

        // Keep overview and dashboard breakdown cards on the same compact grid.
        return panelCard(height: 170) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("panel.today"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(PanelTheme.text3)
            }
            VStack(spacing: rowSpacing) {
                ForEach(values) { item in
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(PanelTheme.text)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(QuotaFormatters.localizedTokens(item.value, language: language.language))
                            .font(.system(size: 10, weight: .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9.5, weight: .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(height: rowHeight)
                }
                if values.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(PanelTheme.text3)
                        .frame(height: rowHeight, alignment: .leading)
                }
            }
            .padding(.top, 3)
        }
    }

    private var tokenPage: some View {
        let dashboard = tokenDashboard
        return VStack(alignment: .leading, spacing: 14) {
            tokenHeading
            tokenMetricStrip(dashboard)
            tokenChartCard()
            tokenRankings(dashboard)
            tokenHeatmapCard
        }
        .onAppear { selectAvailableTokenPeriodIfNeeded() }
    }

    private var tokenHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(language.text("panel.tokensPageTitle"))
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(PanelTheme.text)
            Spacer(minLength: 8)
            tokenPeriodPicker
        }
        .frame(height: 26, alignment: .center)
    }

    private func tokenMetricStrip(_ dashboard: TokenDashboardSnapshot) -> some View {
        HStack(spacing: 0) {
            metricCell(language.text("tokens.total"), QuotaFormatters.localizedTokens(dashboard.total, language: language.language), large: true)
            metricCell(language.text("tokens.average"), QuotaFormatters.localizedTokens(dashboard.average, language: language.language), large: false)
            metricCell(language.text("tokens.peak"), QuotaFormatters.localizedTokens(dashboard.peak, language: language.language), large: false)
            metricCell(language.text("tokens.topPlatform"), dashboard.platform.first?.name ?? "--", large: false)
            metricCell(language.text("tokens.topModel"), dashboard.models.first?.model ?? "--", large: false)
        }
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PanelTheme.border, lineWidth: 0.5))
    }

    private func metricCell(_ label: String, _ value: String, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(PanelTheme.text3)
            Text(value)
                .font(.system(size: large ? 21 : 16, weight: .semibold))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .overlay(alignment: .trailing) {
            Rectangle().fill(PanelTheme.separator).frame(width: 0.5, height: 38)
        }
    }

    private func tokenChartCard() -> some View {
        let chart = tokenChartSnapshot()
        let axisIndices = chartAxisIndices(for: chart.rows)
        return panelCard(spacing: 6, topPadding: 10, bottomPadding: 8) {
            // Keep the title and the segmented control on one visual centerline.
            // The whole header starts slightly higher because the control is
            // taller than the title, keeping the title's visible glyphs aligned
            // with the 16pt title inset used by the other cards.
            HStack(alignment: .center, spacing: 10) {
                Text(language.text(tokenChartDimension == .platform ? "panel.tokenTrendPlatformTitle" : "panel.tokenTrendModelTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer(minLength: 6)
                tokenChartDimensionPicker
                Text(language.text("tokens.peakValue", QuotaFormatters.localizedTokens(chart.rows.map { $0.total }.max() ?? 0, language: language.language)))
                    .font(.system(size: 10, weight: .regular))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text3)
            }
            StackedBarChart(
                rows: chart.rows,
                todayLabel: language.text("panel.today"),
                tokenLabel: language.text("panel.totalTokens"),
                language: language.language,
                showsSingleSegmentBreakdown: tokenChartDimension == .platform
            )
                .frame(height: 140)
                .padding(.top, 1)
                // tooltip 会在趋势图边界外展开；提升整个图表容器，避免下面的图例覆盖浮层。
                .zIndex(10)
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 44, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(axisIndices, id: \.self) { index in
                        let row = chart.rows[index]
                        let x = 40 + (CGFloat(index) + 0.5) / CGFloat(max(chart.rows.count, 1)) * plotWidth
                        Text(row.isToday ? language.text("panel.today") : row.label)
                            .font(.system(size: 8.5, weight: row.isToday ? .semibold : .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(row.isToday ? PanelTheme.codex : PanelTheme.text3)
                            .lineLimit(1)
                            .fixedSize()
                            .position(x: x, y: 5)
                    }
                }
            }
            .frame(height: 10)
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(chart.legend) { item in
                            legendItem(item.color, item.name)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(minWidth: max(proxy.size.width - 4, 0), alignment: .center)
                }
            }
            .frame(height: 18)
            // Leave a clear breathing space between the x-axis tick labels
            // and the secondary legend row.
            .padding(.top, 5)
            if chart.legend.isEmpty {
                Text(language.text("panel.modelNoData"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.text3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func tokenRankings(_ dashboard: TokenDashboardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            rankingCard(title: language.text("tokens.platformUsage"), items: dashboard.platform)
            rankingCard(title: language.text("tokens.modelUsage"), items: modelRankingItems(from: dashboard.models))
        }
    }

    private func modelRankingItems(from rows: [ModelRow]) -> [BreakdownItem] {
        let colors = categoryColors(for: rows.map { row in
            TokenChartCategory(
                id: "model|\(row.model)",
                name: row.model,
                preferredPaletteIndex: stablePaletteIndex(for: row.model)
            )
        })
        return rows.map {
            BreakdownItem(
                name: $0.model,
                value: $0.total,
                share: $0.share,
                color: colors["model|\($0.model)"] ?? PanelTheme.modelFallback
            )
        }
    }

    private func rankingCard(title: String, items: [BreakdownItem]) -> some View {
        panelCard(height: 170) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 5) {
                ForEach(items.prefix(5)) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 10.5))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text)
                            .lineLimit(1)
                            .frame(width: 108, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(PanelTheme.surface2)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(item.color)
                                        .frame(width: max(proxy.size.width * item.share, 2))
                                }
                        }
                        .frame(height: 4)
                        Text(QuotaFormatters.localizedTokens(item.value, language: language.language))
                            .font(.system(size: 9.5))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                            .frame(width: 54, alignment: .trailing)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(height: 17)
                }
                if items.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(PanelTheme.text3)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var tokenHeatmapCard: some View {
        let snapshot = yearHeatmapSnapshot
        return panelCard {
            HStack(alignment: .bottom, spacing: 8) {
                Text(language.text("tokens.yearTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                HStack(spacing: 4) {
                    Text(language.text("tokens.less"))
                        .font(.system(size: 9))
                        .foregroundStyle(PanelTheme.text3)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(heatColor(level: level))
                            .frame(width: 9, height: 9)
                    }
                    Text(language.text("tokens.more"))
                        .font(.system(size: 9))
                        .foregroundStyle(PanelTheme.text3)
                }
            }
            GeometryReader { proxy in
                let leadingWidth: CGFloat = 26
                let gap: CGFloat = 3
                let plotWidth = max(proxy.size.width - leadingWidth, 1)
                let cellWidth = max((plotWidth - gap * 52) / 53, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(snapshot.months) { month in
                        Text(monthLabel(for: month.date))
                        .font(.system(size: 8.5))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text3)
                            .fixedSize()
                            .offset(x: leadingWidth + CGFloat(month.column) * (cellWidth + gap))
                    }
                }
            }
            .frame(height: 10)
            .padding(.top, 9)
            HStack(alignment: .top, spacing: 7) {
                VStack(spacing: 3) {
                    ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 19, height: 9, alignment: .leading)
                    }
                }
                TokenYearHeatmap(
                    levels: snapshot.levels,
                    values: snapshot.values,
                    labels: snapshot.labels,
                    leadingOffset: snapshot.leadingOffset,
                    language: language.language
                )
                    .frame(height: 81)
            }
            .padding(.top, 2)
        }
    }

    private var weekdayLabels: [String] {
        language.language == .simplifiedChinese
            ? ["一", "", "三", "", "五", "", "日"]
            : ["M", "", "W", "", "F", "", "S"]
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private var yearHeatmapSnapshot: YearHeatmapSnapshot {
        let rows = DailyTokenUsage.filledHistory(from: store.totalTokenHistory, endingAt: .now, dayCount: 365)
        let peak = max(rows.map(\.total).max() ?? 1, 1)
        let levels = rows.map { row in
            guard row.total > 0 else { return 0 }
            let ratio = Double(row.total) / Double(peak)
            if ratio > 0.75 { return 4 }
            if ratio > 0.5 { return 3 }
            if ratio > 0.25 { return 2 }
            return 1
        }
        guard let first = rows.first?.day, let last = rows.last?.day else {
            return YearHeatmapSnapshot(levels: levels, values: rows.map(\.total), labels: [], leadingOffset: 0, months: [])
        }

        let layout = CalendarHeatmapLayout(start: first, end: last)
        return YearHeatmapSnapshot(
            levels: levels,
            values: rows.map(\.total),
            labels: rows.map { heatmapDayLabel(for: $0.day) },
            leadingOffset: layout.leadingOffset,
            months: layout.months
        )
    }

    private func heatmapDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateFormat = language.language == .simplifiedChinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    private func heatColor(level: Int) -> Color {
        switch level {
        case 1: PanelTheme.codex.opacity(0.20)
        case 2: PanelTheme.codex.opacity(0.42)
        case 3: PanelTheme.codex.opacity(0.68)
        case 4: PanelTheme.codex
        default: PanelTheme.surface
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("settings.title"))
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 14) {
                settingsCard {
                    settingsRow(title: language.text("settings.launchAtLogin"), detail: language.text("settings.launchAtLogin.detail")) {
                        CustomToggle(isOn: Binding(
                            get: { loginItem.isRegistered },
                            set: { loginItem.setEnabled($0) }
                        ))
                    }
                    settingsRow(title: language.text("settings.language"), detail: language.text("settings.language.detail")) {
                        PanelSegmentedControl(
                            options: AppLanguage.allCases,
                            selection: $language.language
                        ) { value in
                            value == .simplifiedChinese ? "简体中文" : "English"
                        }
                    }
                    settingsRow(title: language.text("settings.dockIcon"), detail: language.text("settings.dockIcon.detail")) {
                        PanelSegmentedControl(
                            options: DockIconMode.allCases,
                            selection: $dockIconSettings.mode
                        ) { mode in
                            switch mode {
                            case .smart: language.text("settings.dockIcon.smart")
                            case .always: language.text("settings.dockIcon.always")
                            case .never: language.text("settings.dockIcon.never")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PanelTheme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func settingsRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PanelTheme.text)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(PanelTheme.text3)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PanelTheme.separator).frame(height: 0.5).padding(.horizontal, 15)
        }
    }

    private var overviewRows: [DayRow] {
        makeDayRows(dayCount: 7)
    }

    private var tokenDashboard: TokenDashboardSnapshot {
        let rows = dayRows
        let presentation = store.tokenDashboardSnapshot(for: tokenPeriod.presentationPeriod)
        return TokenDashboardSnapshot(
            rows: rows,
            total: presentation.summary.total,
            average: presentation.summary.average,
            peak: presentation.summary.peak,
            platform: presentation.platform.map { row in
                BreakdownItem(
                    name: row.key.displayName(
                        claudeCode: language.text("panel.claudeCode"),
                        other: language.text("tokens.otherPlatform")
                    ),
                    value: row.total,
                    share: row.share,
                    color: breakdownColor(for: row.key)
                )
            },
            models: presentation.models.map { row in
                ModelRow(
                    model: row.key.displayName(other: language.text("tokens.otherModel")),
                    total: row.total,
                    share: row.share
                )
            }
        )
    }

    private func chartAxisIndices(for rows: [TokenChartRow]) -> [Int] {
        guard !rows.isEmpty else { return [] }
        guard rows.count > 7 else { return Array(rows.indices) }
        let last = rows.count - 1
        return [0, last / 4, last / 2, last * 3 / 4, last]
    }

    private var tokenChartDimensionPicker: some View {
        PanelSegmentedControl(
            options: TokenChartDimension.allCases,
            selection: $tokenChartDimension
        ) { dimension in
            language.text(dimension.localizationKey)
        }
    }

    private var hourlyChartAxisIndices: [Int] {
        [0, 4, 8, 12, 16, 20]
    }

    private func hourlyTokenChartSnapshot() -> TokenChartSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let buckets = store.tokenBuckets.filter {
            calendar.isDate($0.bucketStart, inSameDayAs: today) && $0.total > 0
        }
        var valuesByHour: [Int: Int] = [:]
        for bucket in buckets {
            let hour = calendar.component(.hour, from: bucket.bucketStart)
            valuesByHour[hour, default: 0] += bucket.total
        }
        let rows = (0..<24).map { hour in
            let value = valuesByHour[hour] ?? 0
            let segments = value > 0
                ? [TokenChartSegment(
                    id: "hourly-total",
                    name: language.text("panel.totalTokens"),
                    value: value,
                    color: PanelTheme.codex
                )]
                : []
            return TokenChartRow(
                id: "hour-\(hour)",
                label: String(format: "%02d:00-%02d:00", hour, (hour + 1) % 24),
                isToday: false,
                segments: segments
            )
        }
        return TokenChartSnapshot(rows: rows, legend: [])
    }

    private func tokenChartSnapshot() -> TokenChartSnapshot {
        let chartStart = tokenChartStartDate
        let dayCount = tokenChartDayCount(startingAt: chartStart)
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        let filteredBuckets = store.tokenBuckets.filter { bucket in
            let day = calendar.startOfDay(for: bucket.bucketStart)
            return day >= chartStart && day <= end && bucket.total > 0
        }

        let categories = Dictionary(
            filteredBuckets.map { chartCategory(for: $0) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let totalsByCategory = filteredBuckets.reduce(into: [String: Int]()) { totals, bucket in
            let category = chartCategory(for: bucket)
            totals[category.id, default: 0] += bucket.total
        }
        let sortedCategoryIDs = totalsByCategory.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map(\.key)
        // The trend chart is the detailed view: show every platform and model
        // category. The compact four-plus-other grouping belongs to the lists
        // below the chart, not to this chart or its legend.
        let chartCategoryIDs = Set(sortedCategoryIDs)
        let visibleCategories = categories.values.filter { chartCategoryIDs.contains($0.id) }
        let categoryColors = categoryColors(for: Array(visibleCategories))

        var valuesByDay: [String: [String: Int]] = [:]
        for bucket in filteredBuckets {
            let category = chartCategory(for: bucket)
            let dayKey = DailyTokenUsage.dayKey(for: calendar.startOfDay(for: bucket.bucketStart))
            valuesByDay[dayKey, default: [:]][category.id, default: 0] += bucket.total
        }

        let rows: [TokenChartRow] = (0..<dayCount).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index - (dayCount - 1), to: end) else { return nil }
            let dayKey = DailyTokenUsage.dayKey(for: day)
            let values = valuesByDay[dayKey] ?? [:]
            let segments = values.compactMap { id, value -> TokenChartSegment? in
                guard value > 0 else { return nil }
                guard let category = categories[id] else { return nil }
                return TokenChartSegment(
                    id: category.id,
                    name: category.name,
                    value: value,
                    color: categoryColors[category.id] ?? PanelTheme.modelFallback
                )
            }
            .sorted { $0.id < $1.id }
            return TokenChartRow(
                id: dayKey,
                label: chartLabel(for: day),
                isToday: dayKey == DailyTokenUsage.dayKey(for: .now),
                segments: segments
            )
        }

        let displayedTotals = rows.flatMap(\.segments).reduce(into: [String: Int]()) { totals, segment in
            totals[segment.id, default: 0] += segment.value
        }
        let legendCategories = rows.flatMap(\.segments)
            .reduce(into: [String: TokenChartLegendItem]()) { result, segment in
                result[segment.id] = TokenChartLegendItem(id: segment.id, name: segment.name, color: segment.color)
            }
            .values
            .sorted { lhs, rhs in
                let left = displayedTotals[lhs.id] ?? totalsByCategory[lhs.id] ?? 0
                let right = displayedTotals[rhs.id] ?? totalsByCategory[rhs.id] ?? 0
                if left != right { return left > right }
                return lhs.id < rhs.id
            }

        return TokenChartSnapshot(rows: rows, legend: legendCategories)
    }

    private var tokenChartStartDate: Date {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        if let fixedDayCount = tokenPeriod.fixedDayCount {
            return calendar.date(byAdding: .day, value: -(fixedDayCount - 1), to: end) ?? end
        }
        let earliest = (store.tokenBuckets.map(\.bucketStart) + store.totalTokenHistory.map(\.day)).min()
        return earliest.map(calendar.startOfDay) ?? end
    }

    private func tokenChartDayCount(startingAt start: Date) -> Int {
        let end = Calendar.current.startOfDay(for: .now)
        return max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0, 0) + 1
    }

    private func chartLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateFormat = tokenPeriod == .all ? "MM-dd" : "MM-dd"
        return formatter.string(from: date)
    }

    private func categoryColors(for categories: [TokenChartCategory]) -> [String: Color] {
        let palette = PanelTheme.categoryPaletteExtended
        return Dictionary(
            categories.map { category in
                (category.id, palette[category.preferredPaletteIndex % palette.count])
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func stablePaletteIndex(for value: String) -> Int {
        let hash = value.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return Int(hash % UInt32(PanelTheme.categoryPaletteExtended.count))
    }

    private func stableCategoryColor(for value: String) -> Color {
        PanelTheme.categoryPaletteExtended[stablePaletteIndex(for: value)]
    }

    private func chartCategory(for bucket: TokenUsageBucket) -> TokenChartCategory {
        chartCategory(for: bucket, dimension: tokenChartDimension)
    }

    private func chartCategory(for bucket: TokenUsageBucket, dimension: TokenChartDimension) -> TokenChartCategory {
        switch dimension {
        case .platform:
            let key = UsageBreakdownKey.platformClient(platform: bucket.platform, client: bucket.client)
            let paletteIndex: Int
            switch (bucket.platform, bucket.client) {
            case (.codex, _): paletteIndex = 0
            case (.claude, .cli): paletteIndex = 2
            case (.claude, _): paletteIndex = 1
            case (.workbuddy, _): paletteIndex = 3
            default: paletteIndex = stablePaletteIndex(for: bucket.platform.rawValue)
            }
            return TokenChartCategory(
                id: key.stableID,
                name: key.displayName(claudeCode: language.text("panel.claudeCode")),
                preferredPaletteIndex: paletteIndex
            )
        case .model:
            let model = TokenModelName.canonical(bucket.model)
            return TokenChartCategory(
                id: "model|\(model)",
                name: model,
                preferredPaletteIndex: stablePaletteIndex(for: model)
            )
        }
    }

    private struct BreakdownItem: Identifiable {
        let name: String
        let value: Int
        let share: Double
        let color: Color

        var id: String { name }
    }

    private struct TokenChartCategory {
        let id: String
        let name: String
        let preferredPaletteIndex: Int
    }

    fileprivate struct TokenChartSegment: Identifiable {
        let id: String
        let name: String
        let value: Int
        let color: Color
    }

    fileprivate struct TokenChartRow: Identifiable {
        let id: String
        let label: String
        let isToday: Bool
        let segments: [TokenChartSegment]

        var total: Int { segments.reduce(0) { $0 + $1.value } }
    }

    private struct TokenChartLegendItem: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    private struct TokenChartSnapshot {
        let rows: [TokenChartRow]
        let legend: [TokenChartLegendItem]
    }

    private struct TokenDashboardSnapshot {
        let rows: [DayRow]
        let total: Int
        let average: Int
        let peak: Int
        let platform: [BreakdownItem]
        let models: [ModelRow]
    }

    private struct YearHeatmapSnapshot {
        let levels: [Int]
        let values: [Int]
        let labels: [String]
        let leadingOffset: Int
        let months: [CalendarHeatmapLayout.MonthMarker]
    }

    private var tokenPeriodPicker: some View {
        PanelSegmentedControl(
            options: TokenPeriod.allCases,
            selection: $tokenPeriod,
            isEnabled: tokenPeriodIsAvailable,
            disabledHelp: { _ in language.text("panel.insufficientHistory") }
        ) { period in
            language.text(period.localizationKey)
        }
    }

    private func tokenPeriodIsAvailable(_ period: TokenPeriod) -> Bool {
        let history = store.presentationSnapshot.history
        return switch period {
        case .sevenDays: history.supportsSevenDays
        case .thirtyDays: history.supportsThirtyDays
        case .ninetyDays: history.supportsNinetyDays
        case .all: history.recordedDayCount > 0
        }
    }

    private func selectAvailableTokenPeriodIfNeeded() {
        guard !tokenPeriodIsAvailable(tokenPeriod) else { return }
        if tokenPeriodIsAvailable(.all) {
            tokenPeriod = .all
        }
    }

    private var emptyState: some View {
        Group {
            if store.isRefreshing || store.isRefreshingTokenSources {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(language.text("panel.syncingTitle"))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(PanelTheme.text)
                            Text(loadingProgressText)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(PanelTheme.text2)
                        }
                        Spacer()
                        if let progress = store.localTokenRefreshProgress {
                            Text("\(Int(progress.fraction * 100))%")
                                .font(.system(size: 12, weight: .semibold))
                                .fontDesign(.monospaced)
                                .foregroundStyle(PanelTheme.codex)
                        }
                    }
                    ProgressView(value: store.localTokenRefreshProgress?.fraction ?? 0.05)
                        .tint(PanelTheme.codex)

                    HStack(spacing: 12) {
                        loadingPlaceholder(height: 92)
                        loadingPlaceholder(height: 92)
                        loadingPlaceholder(height: 92)
                    }
                    loadingPlaceholder(height: 190)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(PanelTheme.background)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.shield")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(PanelTheme.codex)
                    Text(language.text("panel.noDataTitle"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PanelTheme.text)
                    Text(language.text("panel.noDataDetail"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(PanelTheme.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)
                    Button(language.text("panel.retry")) {
                        Task { await store.refreshAll() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PanelTheme.codex)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PanelTheme.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingProgressText: String {
        guard let progress = store.localTokenRefreshProgress else {
            return language.text("panel.syncingDetail")
        }
        return language.text(
            "panel.statusProgress",
            progress.completedSources,
            progress.totalSources
        )
    }

    private func loadingPlaceholder(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(PanelTheme.surface)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(PanelTheme.border, lineWidth: 0.5)
            )
            .opacity(reduceMotion ? 0.72 : 0.88)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PanelTheme.danger)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelTheme.text2)
            Spacer(minLength: 8)
            Text(language.text("panel.showingLastData"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelTheme.text3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(PanelTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sharedBalanceText: String {
        guard let balance = store.deepSeekBalance else { return "--" }
        return QuotaFormatters.money(balance, currency: store.deepSeekCurrency)
    }

    private var codexProvider: ProviderUsage? {
        store.providers.first { $0.providerId.lowercased() == "codex" }
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(PanelTheme.text3)
        }
    }

    // MARK: 数据行

    struct DayRow: Identifiable {
        let id: String
        let label: String
        let isToday: Bool
        let codex: Int
        let codexDeepSeek: Int
        let claude: Int
        let claudeDeepSeek: Int
        let claudeCode: Int
        let claudeCodeDeepSeek: Int
        let workbuddy: Int
        let workbuddyDeepSeek: Int

        var deepSeek: Int {
            codexDeepSeek + claudeDeepSeek + claudeCodeDeepSeek + workbuddyDeepSeek
        }

        var total: Int { codex + claude + claudeCode + workbuddy }
    }

    struct ModelRow: Identifiable {
        let model: String
        let total: Int
        let share: Double

        var id: String { model }
    }

    private func byDay(_ history: [DailyTokenUsage]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0.total) })
    }

    private var dayRows: [DayRow] {
        makeDayRows(dayCount: tokenPeriod == .all ? allHistoryDayCount : tokenPeriod.dayCount)
    }

    private var allHistoryDayCount: Int {
        guard let earliest = store.totalTokenHistory.map(\.day).min() else { return 1 }
        let start = Calendar.current.startOfDay(for: earliest)
        let end = Calendar.current.startOfDay(for: .now)
        return max((Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
    }

    private func makeDayRows(dayCount: Int) -> [DayRow] {
        let todayKey = DailyTokenUsage.dayKey(for: .now)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let codex = byDay(store.tokenHistory)
        let codexDS = byDay(store.codexDeepSeekHistory)
        let claude = byDay(store.claudeDesktopHistory)
        let claudeDS = byDay(store.desktopDeepSeekHistory)
        let claudeCode = byDay(store.claudeHistory)
        let claudeCodeDS = byDay(store.claudeDeepSeekHistory)
        let workbuddy = byDay(store.workBuddyHistory)
        let workbuddyDS = byDay(store.workbuddyDeepSeekHistory)
        let filled = DailyTokenUsage.filledHistory(
            from: store.totalTokenHistory,
            endingAt: .now,
            dayCount: dayCount
        )
        return filled.map { usage in
            let id = usage.id
            return DayRow(
                id: id,
                label: formatter.string(from: usage.day),
                isToday: id == todayKey,
                codex: codex[id] ?? 0,
                codexDeepSeek: codexDS[id] ?? 0,
                claude: claude[id] ?? 0,
                claudeDeepSeek: claudeDS[id] ?? 0,
                claudeCode: claudeCode[id] ?? 0,
                claudeCodeDeepSeek: claudeCodeDS[id] ?? 0,
                workbuddy: workbuddy[id] ?? 0,
                workbuddyDeepSeek: workbuddyDS[id] ?? 0
            )
        }
    }

    private func panelCard(
        height: CGFloat? = nil,
        spacing: CGFloat = 12,
        topPadding: CGFloat = 16,
        bottomPadding: CGFloat = 16,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 16)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(PanelTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PanelTheme.border, lineWidth: 0.5))
    }
}

// MARK: - 标题栏右侧状态

struct TitlebarStatusView: View {
    let store: QuotaStore
    let language: LanguageSettings

    private var isUpdating: Bool {
        store.isRefreshing || store.isRefreshingTokenSources
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PanelTheme.text2)
                .lineLimit(1)
        }
        .frame(height: 24)
        .padding(.horizontal, 6)
    }

    private var statusColor: Color {
        if isUpdating { return PanelTheme.codex }
        return switch store.presentationSnapshot.availability {
        case .ready: PanelTheme.ok
        case .stale, .connectedOnly: PanelTheme.warn
        case .loading: PanelTheme.codex
        case .unavailable, .error: PanelTheme.danger
        }
    }

    private var statusText: String {
        if let progress = store.localTokenRefreshProgress {
            return language.text(
                "panel.statusProgress",
                progress.completedSources,
                progress.totalSources
            )
        }
        if isUpdating {
            return language.text("panel.syncingTitle")
        }
        guard let date = store.latestUpdatedAt else {
            return language.text("panel.updated", "--:--")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return language.text("panel.updated", formatter.string(from: date))
    }

}

// MARK: - 控件

private enum PanelSegmentedMetrics {
    static let segmentWidth: CGFloat = 60
    static let height: CGFloat = 26
    static let cornerRadius: CGFloat = 6
}

private struct PanelSegmentedControl<Option: Hashable>: View {

    let options: [Option]
    @Binding var selection: Option
    let isEnabled: (Option) -> Bool
    let disabledHelp: ((Option) -> String)?
    let label: (Option) -> String

    @Namespace private var selectionIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        options: [Option],
        selection: Binding<Option>,
        isEnabled: @escaping (Option) -> Bool = { _ in true },
        disabledHelp: ((Option) -> String)? = nil,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        _selection = selection
        self.isEnabled = isEnabled
        self.disabledHelp = disabledHelp
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let enabled = isEnabled(option)
                Button {
                    guard enabled, selection != option else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        selection = option
                    }
                } label: {
                    ZStack {
                        if selection == option {
                            RoundedRectangle(cornerRadius: PanelSegmentedMetrics.cornerRadius, style: .continuous)
                                .fill(PanelTheme.surface)
                                .frame(width: PanelSegmentedMetrics.segmentWidth, height: PanelSegmentedMetrics.height)
                                .shadow(color: PanelTheme.shadowSmall, radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selection", in: selectionIndicator)
                        }
                        Text(label(option))
                            .font(.system(size: 11, weight: selection == option ? .semibold : .regular))
                            .foregroundStyle(
                                enabled
                                    ? (selection == option ? PanelTheme.text : PanelTheme.text2)
                                    : PanelTheme.text3
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: PanelSegmentedMetrics.segmentWidth, height: PanelSegmentedMetrics.height)
                    .contentShape(RoundedRectangle(cornerRadius: PanelSegmentedMetrics.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(enabled ? "" : (disabledHelp?(option) ?? ""))
            }
        }
        .padding(2)
        .background(PanelTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.border, lineWidth: 0.5))
    }
}

private struct CustomToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? PanelTheme.codex : PanelTheme.surface3)
                .frame(width: 32, height: 19)
            Circle()
                .fill(.white)
                .frame(width: 15, height: 15)
                .padding(2)
                .shadow(color: PanelTheme.shadowSmall, radius: 1, y: 0.5)
        }
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - 图表提示

private struct ChartTooltipItem: Identifiable {
    let label: String
    let value: String
    let color: Color

    var id: String { label }
}

private struct ChartTooltipSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private enum ChartTooltipLayout {
    // Keep the tooltip at least 140pt wide, expand for longer labels up to
    // 400pt, and let labels truncate at the trailing edge beyond that cap.
    static let minimumWidth: CGFloat = 140
    static let maximumWidth: CGFloat = 400
    static let initialSize = CGSize(width: minimumWidth, height: 46)

    static func resolvedWidth(
        title: String,
        value: String,
        valueLabel: String?,
        items: [ChartTooltipItem]
    ) -> CGFloat {
        let headerWidth = textWidth(title, font: .monospacedSystemFont(ofSize: 10, weight: .medium))
            + 8
            + 6
            + textWidth(value, font: .monospacedSystemFont(ofSize: 11.5, weight: .semibold))

        let detailWidth: CGFloat
        if items.isEmpty {
            detailWidth = valueLabel.map { textWidth($0, font: .systemFont(ofSize: 9)) } ?? 0
        } else {
            detailWidth = items.map { item in
                6
                    + 6
                    + textWidth(item.label, font: .systemFont(ofSize: 9.5))
                    + 6
                    + textWidth(item.value, font: .monospacedSystemFont(ofSize: 9.5, weight: .regular))
            }.max() ?? 0
        }

        return min(max(ceil(max(headerWidth, detailWidth) + 20), minimumWidth), maximumWidth)
    }

    private static func textWidth(_ value: String, font: NSFont) -> CGFloat {
        ceil((value as NSString).size(withAttributes: [.font: font]).width)
    }
}

private struct ChartTooltip: View {
    let title: String
    let value: String
    let valueLabel: String?
    let items: [ChartTooltipItem]

    init(title: String, value: String, valueLabel: String?, items: [ChartTooltipItem] = []) {
        self.title = title
        self.value = value
        self.valueLabel = valueLabel
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text2)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(value)
                    .font(.system(size: 11.5, weight: .semibold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text)
            }
            if !items.isEmpty {
                Rectangle()
                    .fill(PanelTheme.separator)
                    .frame(height: 1)
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)
                            Text(item.label)
                                .font(.system(size: 9.5))
                                .foregroundStyle(PanelTheme.text2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(item.value)
                                .font(.system(size: 9.5))
                                .fontDesign(.monospaced)
                                .foregroundStyle(PanelTheme.text)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            } else if let valueLabel {
                Text(valueLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(PanelTheme.text3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // 依据当前内容在 140pt 下限与 400pt 上限之间自适应，超长标签单行尾部省略。
        .frame(
            width: ChartTooltipLayout.resolvedWidth(
                title: title,
                value: value,
                valueLabel: valueLabel,
                items: items
            ),
            alignment: .leading
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ChartTooltipSizePreferenceKey.self, value: proxy.size)
            }
        }
        // 使用完全不透明的面板底色，浮层经过图例或其他内容时不再透叠。
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 0.9))
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        .zIndex(20)
        .allowsHitTesting(false)
    }
}

// MARK: - 折线图

private struct Sparkline: View {
    let values: [Double]
    let labels: [String]
    let color: Color
    let valueLabel: String
    let language: AppLanguage
    @State private var hoveredIndex: Int?
    @State private var tooltipSize = ChartTooltipLayout.initialSize

    var body: some View {
        GeometryReader { proxy in
            let peak = max(values.max() ?? 0, 1)
            let plotTopInset: CGFloat = 15
            let axisLabelOffset: CGFloat = 18
            let plotBottomInset: CGFloat = axisLabelOffset + 10
            let plotHeight = max(proxy.size.height - plotTopInset - plotBottomInset, 1)
            let plotX: CGFloat = 40
            let plotWidth = max(proxy.size.width - 44, 1)
            let slotWidth = plotWidth / CGFloat(max(values.count, 1))
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: plotX + (CGFloat(index) + 0.5) * slotWidth,
                    y: plotTopInset + plotHeight - CGFloat(value / peak) * plotHeight
                )
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let plot = CGRect(x: plotX, y: plotTopInset, width: plotWidth, height: plotHeight)
                    for line in 0...3 {
                        let y = plot.minY + plot.height * CGFloat(line) / 3
                        var path = Path()
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        context.stroke(
                            path,
                            with: .color(PanelTheme.grid),
                            style: StrokeStyle(lineWidth: 1, dash: line == 3 ? [] : [4, 4])
                        )
                    }

                    if let hoveredIndex, points.indices.contains(hoveredIndex) {
                        let highlightRect = CGRect(
                            x: plot.minX + CGFloat(hoveredIndex) * slotWidth + 2,
                            y: plot.minY,
                            width: max(slotWidth - 4, 1),
                            height: plot.height
                        )
                        context.fill(
                            Path(roundedRect: highlightRect, cornerRadius: 5),
                            with: .color(PanelTheme.text.opacity(0.045))
                        )
                    }

                    guard points.count > 1 else { return }
                    context.fill(
                        smoothPath(points, closeToBottom: plot.maxY),
                        with: .color(color.opacity(0.10))
                    )
                    context.stroke(
                        smoothPath(points),
                        with: .color(color),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }

                VStack(alignment: .trailing, spacing: 0) {
                    Text(QuotaFormatters.localizedTokens(Int(peak), language: language))
                    Spacer()
                    Text(QuotaFormatters.localizedTokens(Int(peak * 2 / 3), language: language))
                    Spacer()
                    Text(QuotaFormatters.localizedTokens(Int(peak / 3), language: language))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 8.5))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text3)
                .frame(width: 32, height: plotHeight, alignment: .topTrailing)
                .position(x: 16, y: plotTopInset + plotHeight / 2)

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let emphasized = hoveredIndex == nil || hoveredIndex == index
                    Circle()
                        .fill(PanelTheme.surface)
                        .overlay(
                            Circle().stroke(
                                color.opacity(emphasized ? 1 : 0.42),
                                lineWidth: hoveredIndex == index ? 2.5 : 2
                            )
                        )
                        .frame(width: hoveredIndex == index ? 9 : 7, height: hoveredIndex == index ? 9 : 7)
                        .position(point)
                }

                ForEach(axisIndices, id: \.self) { index in
                    if labels.indices.contains(index), points.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: 8.5))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .fixedSize()
                            .position(x: points[index].x, y: plotTopInset + plotHeight + axisLabelOffset)
                    }
                }
                if let hoveredIndex,
                   values.indices.contains(hoveredIndex),
                   labels.indices.contains(hoveredIndex),
                   points.indices.contains(hoveredIndex) {
                    let point = points[hoveredIndex]
                    ChartTooltip(
                        title: labels[hoveredIndex],
                        value: QuotaFormatters.localizedTokens(Int(values[hoveredIndex]), language: language),
                        valueLabel: valueLabel
                    )
                    .position(ChartTooltipPlacement.adjacentToBar(
                        barRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8),
                        tooltipSize: tooltipSize,
                        containerSize: proxy.size
                    ))
                }
            }
            .contentShape(Rectangle())
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoveredIndex = index(at: location, plotX: plotX, plotWidth: plotWidth)
                case .ended:
                    hoveredIndex = nil
                @unknown default:
                    hoveredIndex = nil
                }
            }
        }
    }

    private func index(at location: CGPoint, plotX: CGFloat, plotWidth: CGFloat) -> Int? {
        guard !values.isEmpty, location.x >= plotX, location.x <= plotX + plotWidth else { return nil }
        let slotWidth = plotWidth / CGFloat(values.count)
        return min(max(Int((location.x - plotX) / slotWidth), 0), values.count - 1)
    }

    private var axisIndices: [Int] {
        guard !values.isEmpty else { return [] }
        guard values.count > 7 else { return Array(values.indices) }
        let last = values.count - 1
        return [0, last / 3, last * 2 / 3, last]
    }

    private func smoothPath(_ points: [CGPoint], closeToBottom: CGFloat? = nil) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        if let closeToBottom {
            path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: closeToBottom))
            path.addLine(to: CGPoint(x: first.x, y: closeToBottom))
            path.closeSubpath()
        }
        return path
    }
}

private struct StackedBarChart: View {
    let rows: [MainPanelView.TokenChartRow]
    let todayLabel: String
    let tokenLabel: String
    let language: AppLanguage
    let showsSingleSegmentBreakdown: Bool
    @State private var hoveredIndex: Int?
    @State private var tooltipSize = ChartTooltipLayout.initialSize

    init(
        rows: [MainPanelView.TokenChartRow],
        todayLabel: String,
        tokenLabel: String,
        language: AppLanguage = .simplifiedChinese,
        showsSingleSegmentBreakdown: Bool = false
    ) {
        self.rows = rows
        self.todayLabel = todayLabel
        self.tokenLabel = tokenLabel
        self.language = language
        self.showsSingleSegmentBreakdown = showsSingleSegmentBreakdown
    }

    var body: some View {
        GeometryReader { proxy in
            let peak = max(rows.map(\.total).max() ?? 1, 1)
            let plotTopInset: CGFloat = 15
            let plotBottomInset: CGFloat = 2
            let plotHeight = max(proxy.size.height - plotTopInset - plotBottomInset, 1)
            let plotX: CGFloat = 40
            let plotWidth = max(proxy.size.width - 44, 1)
            let slotWidth = plotWidth / CGFloat(max(rows.count, 1))
            let barWidth = min(22, max(slotWidth * 0.64, 0.65))
            let barRects = rows.enumerated().map { index, row in
                let x = plotX + CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
                let height = max(CGFloat(row.total) / CGFloat(peak) * plotHeight, min(1, plotHeight))
                return CGRect(x: x, y: plotTopInset + plotHeight - height, width: barWidth, height: height)
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let plot = CGRect(x: plotX, y: plotTopInset, width: plotWidth, height: plotHeight)
                    for line in 0...3 {
                        let y = plot.minY + plot.height * CGFloat(line) / 3
                        var path = Path()
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        context.stroke(
                            path,
                            with: .color(PanelTheme.grid),
                            style: StrokeStyle(lineWidth: 1, dash: line == 3 ? [] : [4, 4])
                        )
                    }

                    guard !rows.isEmpty else { return }
                    for (index, row) in rows.enumerated() {
                        let x = plot.minX + CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
                        if hoveredIndex == index {
                            let highlightRect = CGRect(
                                x: plot.minX + CGFloat(index) * slotWidth + 2,
                                y: plot.minY,
                                width: max(slotWidth - 4, 1),
                                height: plot.height
                            )
                            context.fill(
                                Path(roundedRect: highlightRect, cornerRadius: 5),
                                with: .color(PanelTheme.text.opacity(0.045))
                            )
                        }
                        var bottom = plot.maxY
                        for segment in row.segments {
                            let value = segment.value
                            let isEmphasized = hoveredIndex == nil || hoveredIndex == index
                            let color = segment.color.opacity(isEmphasized ? 1 : 0.42)
                            let height = max(CGFloat(value) / CGFloat(peak) * plot.height, min(1, plot.height))
                            let rect = CGRect(x: x, y: bottom - height, width: barWidth, height: height)
                            let radius = min(2, min(barWidth / 2, height / 2))
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: radius),
                                with: .color(color)
                            )
                            bottom -= height
                            var separator = Path()
                            separator.move(to: CGPoint(x: x, y: bottom))
                            separator.addLine(to: CGPoint(x: x + barWidth, y: bottom))
                            context.stroke(separator, with: .color(PanelTheme.surface.opacity(0.78)), lineWidth: 0.75)
                        }
                        if hoveredIndex == index {
                            context.stroke(
                                Path(roundedRect: barRects[index], cornerRadius: min(2, barWidth / 2)),
                                with: .color(PanelTheme.text.opacity(0.34)),
                                lineWidth: 1
                            )
                        }
                    }
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(QuotaFormatters.localizedTokens(peak, language: language))
                    Spacer()
                    Text(QuotaFormatters.localizedTokens(peak * 2 / 3, language: language))
                    Spacer()
                    Text(QuotaFormatters.localizedTokens(peak / 3, language: language))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 8.5))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text3)
                .frame(width: 32, height: plotHeight, alignment: .topTrailing)
                .position(x: 16, y: plotTopInset + plotHeight / 2)

                if let hoveredIndex, rows.indices.contains(hoveredIndex) {
                    let row = rows[hoveredIndex]
                    let tooltipItems = (row.segments.count > 1 || showsSingleSegmentBreakdown)
                        ? compactTooltipItems(row.segments)
                        : []
                    let tooltipCenter = ChartTooltipPlacement.adjacentToBar(
                        barRect: barRects[hoveredIndex],
                        tooltipSize: tooltipSize,
                        containerSize: proxy.size
                    )
                    ChartTooltip(
                        title: row.isToday ? todayLabel : row.label,
                        value: QuotaFormatters.localizedTokens(row.total, language: language),
                        valueLabel: tooltipItems.isEmpty ? nil : tokenLabel,
                        items: tooltipItems
                    )
                    .position(x: tooltipCenter.x, y: tooltipCenter.y)
                }
            }
            .contentShape(Rectangle())
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoveredIndex = index(at: location, plotX: plotX, plotWidth: plotWidth)
                case .ended:
                    hoveredIndex = nil
                @unknown default:
                    hoveredIndex = nil
                }
            }
        }
    }

    private func compactTooltipItems(
        _ segments: [MainPanelView.TokenChartSegment]
    ) -> [ChartTooltipItem] {
        let sorted = segments.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let maximumVisible = 10
        let visibleLimit = sorted.count > maximumVisible ? maximumVisible - 1 : maximumVisible
        let visible = Array(sorted.prefix(visibleLimit))
        let remainder = sorted.dropFirst(visibleLimit)
        var items = visible.map { segment in
            ChartTooltipItem(label: segment.name, value: QuotaFormatters.localizedTokens(segment.value, language: language), color: segment.color)
        }
        if !remainder.isEmpty {
            let total = remainder.reduce(0) { $0 + $1.value }
            items.append(ChartTooltipItem(
                label: "others",
                value: QuotaFormatters.localizedTokens(total, language: language),
                color: PanelTheme.modelFallback
            ))
        }
        return items
    }

    private func index(at location: CGPoint, plotX: CGFloat, plotWidth: CGFloat) -> Int? {
        guard !rows.isEmpty, location.x >= plotX, location.x <= plotX + plotWidth else { return nil }
        let slotWidth = plotWidth / CGFloat(rows.count)
        return min(max(Int((location.x - plotX) / slotWidth), 0), rows.count - 1)
    }

}

struct TokenYearHeatmap: View {
    let levels: [Int]
    let values: [Int]
    let labels: [String]
    let leadingOffset: Int
    let language: AppLanguage
    @State private var hoveredIndex: Int?
    @State private var tooltipSize = ChartTooltipLayout.initialSize

    init(
        levels: [Int],
        values: [Int] = [],
        labels: [String] = [],
        leadingOffset: Int,
        language: AppLanguage = .simplifiedChinese
    ) {
        self.levels = levels
        self.values = values
        self.labels = labels
        self.leadingOffset = leadingOffset
        self.language = language
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = cellMetrics(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for (index, level) in levels.enumerated() {
                        let cell = CalendarHeatmapLayout.cell(forDayAt: index, leadingOffset: leadingOffset)
                        guard cell.column < 53 else { continue }
                        let rect = CGRect(
                            x: CGFloat(cell.column) * (metrics.cellWidth + metrics.gap),
                            y: CGFloat(cell.row) * (metrics.cellHeight + metrics.gap),
                            width: metrics.cellWidth,
                            height: metrics.cellHeight
                        )
                        let path = Path(roundedRect: rect, cornerRadius: min(2, min(metrics.cellWidth / 2, metrics.cellHeight / 2)))
                        context.fill(path, with: .color(color(for: level)))
                    }
                }
                if let hoveredIndex,
                   values.indices.contains(hoveredIndex),
                   labels.indices.contains(hoveredIndex) {
                    let cell = CalendarHeatmapLayout.cell(forDayAt: hoveredIndex, leadingOffset: leadingOffset)
                    let anchorX = CGFloat(cell.column) * (metrics.cellWidth + metrics.gap) + metrics.cellWidth / 2
                    let anchorY = CGFloat(cell.row) * (metrics.cellHeight + metrics.gap) + metrics.cellHeight / 2
                    ChartTooltip(
                        title: labels[hoveredIndex],
                        value: QuotaFormatters.localizedTokens(values[hoveredIndex], language: language),
                        valueLabel: nil
                    )
                    .position(
                        x: ChartTooltipPlacement.x(
                            anchorX: anchorX,
                            tooltipWidth: tooltipSize.width,
                            containerWidth: proxy.size.width
                        ),
                        y: ChartTooltipPlacement.y(
                            anchorY: anchorY,
                            tooltipHeight: tooltipSize.height,
                            containerHeight: proxy.size.height
                        )
                    )
                }
            }
            .contentShape(Rectangle())
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoveredIndex = index(at: location, metrics: metrics)
                case .ended:
                    hoveredIndex = nil
                @unknown default:
                    hoveredIndex = nil
                }
            }
        }
    }

    private struct CellMetrics {
        let gap: CGFloat
        let cellWidth: CGFloat
        let cellHeight: CGFloat
    }

    private func cellMetrics(in size: CGSize) -> CellMetrics {
        let gap: CGFloat = 3
        return CellMetrics(
            gap: gap,
            cellWidth: max((size.width - gap * 52) / 53, 1),
            cellHeight: max((size.height - gap * 6) / 7, 1)
        )
    }

    private func index(at location: CGPoint, metrics: CellMetrics) -> Int? {
        let columnStep = metrics.cellWidth + metrics.gap
        let rowStep = metrics.cellHeight + metrics.gap
        let column = Int(location.x / columnStep)
        let row = Int(location.y / rowStep)
        guard column >= 0, column < 53, row >= 0, row < 7 else { return nil }
        guard location.x.truncatingRemainder(dividingBy: columnStep) <= metrics.cellWidth,
              location.y.truncatingRemainder(dividingBy: rowStep) <= metrics.cellHeight else { return nil }
        let index = column * 7 + row - leadingOffset
        return values.indices.contains(index) ? index : nil
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1: PanelTheme.codex.opacity(0.20)
        case 2: PanelTheme.codex.opacity(0.42)
        case 3: PanelTheme.codex.opacity(0.68)
        case 4: PanelTheme.codex
        default: PanelTheme.surface2
    }
}
}
