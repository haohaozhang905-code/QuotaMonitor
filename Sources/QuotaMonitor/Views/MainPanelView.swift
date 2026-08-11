import AppKit
import SwiftUI

extension Notification.Name {
    static let quotaMonitorOpenSettings = Notification.Name("QuotaMonitor.openSettings")
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

// MARK: - 主面板

struct MainPanelView: View {
    let store: QuotaStore
    @Bindable var language: LanguageSettings
    @State private var loginItem = LoginItemManager()
    @State private var selectedPage: DashboardPage = .overview
    @State private var tokenPeriod: TokenPeriod = .sevenDays
    @State private var hoveredPage: DashboardPage?

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            if shouldShowEmptyState {
                emptyState
            } else {
                panelBody
            }
        }
        .background(PanelTheme.background)
        .frame(minWidth: 820, minHeight: 540)
        // 统一使用系统 SF Mono 等宽设计，让整个仪表盘保持稳定的节奏与字宽。
        .fontDesign(.monospaced)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .quotaMonitorOpenSettings)) { _ in
            selectedPage = .settings
        }
    }

    private var titlebar: some View {
        ZStack {
            Text(QuotaMonitorIdentity.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(PanelTheme.text2)
                .offset(y: -2)
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
                .fill(PanelTheme.border)
                .frame(height: 1)
        }
    }

    private var panelBody: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let message = store.errorMessageKey.map({ language.text($0) }) {
                            errorBanner(message: message)
                        }
                        pageContent
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                // 保留滚动能力，但不显示系统滚动条；主面板的内容边界由卡片和留白表达。
                .scrollIndicators(.never)
                .id(selectedPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var shouldShowEmptyState: Bool {
        switch store.presentationSnapshot.availability {
        case .loading, .unavailable, .error: true
        case .ready, .connectedOnly, .stale: false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: MenuBarQuotaGlyph.image)
                    .renderingMode(.original)
                    .resizable()
                    .frame(width: 19, height: 19)
                    .padding(4.5)
                    .background(PanelTheme.deepseekSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(QuotaMonitorIdentity.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            VStack(spacing: 3) {
                ForEach(DashboardPage.allCases, id: \.self) { page in
                    Button {
                        guard selectedPage != page else { return }
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
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
        .frame(width: 198)
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
                    Text(QuotaFormatters.tokensCN(presentation.today.total))
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
                overviewHeroMetric(language.text("overview.last7Total"), QuotaFormatters.tokensCN(presentation.lastSevenDays.total))
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
        let yesterday = store.yesterdayTokenUsage.map { QuotaFormatters.tokensCN($0.total) } ?? "--"
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
        return String(format: language.text("overview.delta"), percent >= 0 ? "↑" : "↓", abs(percent))
    }

    private var relativeDeltaColor: Color {
        guard let today = store.todayTokenUsage?.total,
              let yesterday = store.yesterdayTokenUsage?.total else { return PanelTheme.text2 }
        return today >= yesterday ? PanelTheme.claude : PanelTheme.ok
    }

    private var overviewQuotaGrid: some View {
        HStack(spacing: 10) {
            overviewQuotaCard(
                icon: .codex,
                name: "Codex",
                route: codexOverviewRoute,
                facts: codexOverviewFacts,
                state: codexOverviewState
            )
            overviewQuotaCard(
                icon: .claude,
                name: "Claude",
                route: claudeOverviewRoute,
                facts: claudeOverviewFacts,
                state: claudeOverviewState
            )
        }
    }

    private var codexOverviewRoute: String {
        switch store.codexRoute {
        case .deepseek: language.text("panel.deepSeekRouteTag")
        case .official: language.text("overview.officialConnected")
        case .unknown: language.text("settings.notConnected")
        }
    }

    private var claudeOverviewRoute: String {
        switch store.claudeRoute {
        case .deepseek: language.text("panel.deepSeekRouteTag")
        case .official: "Pro"
        case .unknown: language.text("settings.notConnected")
        }
    }

    private var codexOverviewFacts: [(String, String, String)] {
        if QuotaPresentationPolicy.mode(for: store.codexRoute) == .sharedBalance { return sharedOverviewFacts }
        return [
            (language.text("overview.sessionQuota"), codexProvider?.session?.remainingPercent.map(QuotaFormatters.percent) ?? "--", codexResetText(codexProvider?.session)),
            (language.text("overview.weekQuota"), codexProvider?.weekly?.remainingPercent.map(QuotaFormatters.percent) ?? "--", codexResetText(codexProvider?.weekly))
        ]
    }

    private var claudeOverviewFacts: [(String, String, String)] {
        if QuotaPresentationPolicy.mode(for: store.claudeRoute) == .sharedBalance { return sharedOverviewFacts }
        let detail = store.claudeRoute == .unknown
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
        switch store.claudeRoute {
        case .deepseek: BalanceState(days: store.deepSeekDays)
        case .official: .unknown
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
                            .fill(PanelTheme.border)
                            .frame(width: 1, height: 57)
                            .padding(.horizontal, 13)
                    }
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(PanelTheme.border).frame(height: 1).padding(.top, 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewBottomGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            overviewTrendCard
                .frame(maxWidth: .infinity)
            VStack(spacing: 14) {
                overviewListCard(title: language.text("overview.platform"), values: platformSummaries)
                overviewListCard(title: language.text("overview.model"), values: modelSummaries)
            }
            .frame(maxWidth: .infinity)
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

    private var overviewTrendCard: some View {
        panelCard(height: 274) {
            HStack {
                Text(language.text("overview.last7Title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("overview.last7Note"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(PanelTheme.text3)
            }
            Text(QuotaFormatters.tokensCN(overviewRows.reduce(0) { $0 + $1.total }))
                .font(.system(size: 28, weight: .semibold))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
                .padding(.top, 5)
            Sparkline(
                values: overviewRows.map { Double($0.total) },
                labels: overviewRows.map(\.label),
                color: PanelTheme.codex
            )
                .frame(height: 154)
                .padding(.top, 2)
        }
    }

    private var platformSummaries: [BreakdownItem] {
        store.presentationSnapshot.platformToday.map { row in
            BreakdownItem(
                name: row.key.displayName(claudeCode: language.text("panel.claudeCode")),
                value: row.total,
                share: row.share,
                color: breakdownColor(for: row.key)
            )
        }
    }

    private var modelSummaries: [BreakdownItem] {
        store.presentationSnapshot.modelToday.prefix(3).map { row in
            BreakdownItem(
                name: row.key.displayName(),
                value: row.total,
                share: row.share,
                color: PanelTheme.codex
            )
        }
    }

    private func breakdownColor(for key: UsageBreakdownKey) -> Color {
        switch key {
        case let .platformClient(platform, client):
            switch (platform, client) {
            case (.codex, _): PanelTheme.codex
            case (.claude, .cli): PanelTheme.cclaude
            case (.claude, _): PanelTheme.claude
            case (.workbuddy, _): PanelTheme.workbuddy
            case (.kimi, _): PanelTheme.text2
            }
        case .model, .otherModels: PanelTheme.codex
        }
    }

    private func breakdownItems(_ values: [(String, Int, Color)]) -> [BreakdownItem] {
        let total = values.reduce(0) { $0 + $1.1 }
        return values.filter { $0.1 > 0 }.map { BreakdownItem(name: $0.0, value: $0.1, share: total > 0 ? Double($0.1) / Double(total) : 0, color: $0.2) }
    }

    private func overviewListCard(title: String, values: [BreakdownItem]) -> some View {
        panelCard(height: 130) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("panel.today"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(PanelTheme.text3)
            }
            VStack(spacing: 10) {
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
                        Text(QuotaFormatters.tokensCN(item.value))
                            .font(.system(size: 10, weight: .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9.5, weight: .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                if values.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(PanelTheme.text3)
                }
            }
            .padding(.top, 5)
        }
    }

    private var tokenPage: some View {
        let dashboard = tokenDashboard
        return VStack(alignment: .leading, spacing: 14) {
            tokenHeading
            tokenMetricStrip(dashboard)
            tokenChartCard(rows: dashboard.rows)
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
            metricCell(language.text("tokens.total"), QuotaFormatters.tokensCN(dashboard.total), large: true)
            metricCell(language.text("tokens.average"), QuotaFormatters.tokensCN(dashboard.average), large: false)
            metricCell(language.text("tokens.peak"), QuotaFormatters.tokensCN(dashboard.peak), large: false)
            metricCell(language.text("tokens.topPlatform"), dashboard.platform.first?.name ?? "--", large: false)
            metricCell(language.text("tokens.topModel"), dashboard.models.first?.model ?? "--", large: false)
        }
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
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
            Rectangle().fill(PanelTheme.border).frame(width: 1, height: 38)
        }
    }

    private func tokenChartCard(rows: [DayRow]) -> some View {
        let axisIndices = chartAxisIndices(for: rows)
        return panelCard {
            HStack {
                Text(language.text("tokens.trendTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("tokens.peakValue", QuotaFormatters.tokensCN(rows.map { $0.total }.max() ?? 0)))
                    .font(.system(size: 10, weight: .regular))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text3)
            }
            StackedBarChart(rows: rows, claudeCodeLabel: language.text("panel.claudeCode"))
                .frame(height: 140)
                .padding(.top, 7)
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 44, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(axisIndices, id: \.self) { index in
                        let row = rows[index]
                        let x = 40 + (CGFloat(index) + 0.5) / CGFloat(max(rows.count, 1)) * plotWidth
                        Text(row.isToday ? language.text("panel.today") : row.label)
                            .font(.system(size: 8.5, weight: row.isToday ? .semibold : .regular))
                            .fontDesign(.monospaced)
                            .foregroundStyle(row.isToday ? PanelTheme.codex : PanelTheme.text3)
                            .lineLimit(1)
                            .fixedSize()
                            .position(x: x, y: 7)
                    }
                }
            }
            .frame(height: 14)
            .padding(.top, -2)
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                legendItem(PanelTheme.codex, "Codex")
                legendItem(PanelTheme.claude, "Claude")
                legendItem(PanelTheme.cclaude, language.text("panel.claudeCode"))
                legendItem(PanelTheme.workbuddy, "WorkBuddy")
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    private func tokenRankings(_ dashboard: TokenDashboardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            rankingCard(title: language.text("tokens.platformUsage"), items: dashboard.platform)
            rankingCard(title: language.text("tokens.modelUsage"), items: modelRankingItems(from: dashboard.models))
        }
    }

    private func modelRankingItems(from rows: [ModelRow]) -> [BreakdownItem] {
        let top = rows.prefix(4).map { BreakdownItem(name: $0.model, value: $0.total, share: $0.share, color: PanelTheme.codex) }
        guard rows.count > 4 else { return top }
        let otherTotal = rows.dropFirst(4).reduce(0) { $0 + $1.total }
        let total = rows.reduce(0) { $0 + $1.total }
        return top + [BreakdownItem(
            name: language.text("tokens.otherModel"),
            value: otherTotal,
            share: total > 0 ? Double(otherTotal) / Double(total) : 0,
            color: PanelTheme.text3
        )]
    }

    private func rankingCard(title: String, items: [BreakdownItem]) -> some View {
        panelCard(height: 190) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 12) {
                ForEach(items.prefix(8)) { item in
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
                        Text(QuotaFormatters.tokensCN(item.value))
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
                    leadingOffset: snapshot.leadingOffset
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
                        CustomSegmented(selection: $language.language)
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
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
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
            Rectangle().fill(PanelTheme.border).frame(height: 1).padding(.horizontal, 15)
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
                    name: row.key.displayName(claudeCode: language.text("panel.claudeCode")),
                    value: row.total,
                    share: row.share,
                    color: breakdownColor(for: row.key)
                )
            },
            models: presentation.models.map { row in
                ModelRow(model: row.key.displayName(), total: row.total, share: row.share)
            }
        )
    }

    private func chartAxisIndices(for rows: [DayRow]) -> [Int] {
        guard !rows.isEmpty else { return [] }
        guard rows.count > 5 else { return Array(rows.indices) }
        let last = rows.count - 1
        return [0, last / 4, last / 2, last * 3 / 4, last]
    }

    private struct BreakdownItem: Identifiable {
        let name: String
        let value: Int
        let share: Double
        let color: Color

        var id: String { name }
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
        HStack(spacing: 2) {
            ForEach(TokenPeriod.allCases) { period in
                let isAvailable = tokenPeriodIsAvailable(period)
                Button {
                    guard isAvailable else { return }
                    guard tokenPeriod != period else { return }
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        tokenPeriod = period
                    }
                } label: {
                    Text(language.text(period.localizationKey))
                        .font(.system(size: 11, weight: tokenPeriod == period ? .semibold : .regular))
                        .fontDesign(.monospaced)
                        .foregroundStyle(
                            isAvailable
                                ? (tokenPeriod == period ? PanelTheme.text : PanelTheme.text2)
                                : PanelTheme.text3
                        )
                        .frame(width: 58, height: 22)
                        .background(tokenPeriod == period ? PanelTheme.surface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                .help(isAvailable ? "" : language.text("panel.insufficientHistory"))
            }
        }
        .padding(2)
        .background(PanelTheme.surface2, in: Capsule())
        .overlay(Capsule().stroke(PanelTheme.border, lineWidth: 1))
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
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 12) {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "bolt.shield")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(PanelTheme.codex)
                Text(store.isRefreshing ? language.text("panel.syncingTitle") : language.text("panel.noDataTitle"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PanelTheme.text)
                Text(store.isRefreshing ? language.text("panel.syncingDetail") : language.text("panel.noDataDetail"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PanelTheme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                if !store.isRefreshing {
                    Button(language.text("panel.retry")) {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PanelTheme.codex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PanelTheme.background)
        }
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
                .frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelTheme.text2)
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

    private func panelCard(height: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(PanelTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
    }
}

// MARK: - 标题栏右侧状态

struct TitlebarStatusView: View {
    let store: QuotaStore
    let language: LanguageSettings

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(PanelTheme.ok)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text2)
                .lineLimit(1)
        }
        .frame(height: 24)
        .padding(.horizontal, 6)
    }

    private var statusText: String {
        guard let date = store.lastUpdated else {
            return language.text("panel.updated", "--:--")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return language.text("panel.updated", formatter.string(from: date))
    }
}

// MARK: - 控件

private struct CustomSegmented: View {
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 2) {
            segment(language: .simplifiedChinese, label: "简体中文")
            segment(language: .english, label: "English")
        }
        .padding(3)
        .background(PanelTheme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func segment(language value: AppLanguage, label: String) -> some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(selection == value ? PanelTheme.text : PanelTheme.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                selection == value ? PanelTheme.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .shadow(color: selection == value ? PanelTheme.shadowSmall : .clear, radius: 2, y: 1)
            .contentShape(Rectangle())
            .onTapGesture { selection = value }
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

private enum ChartTooltipPlacement {
    static let gap: CGFloat = 10
    static let edgeInset: CGFloat = 6

    /// 右侧优先；如果右侧放不下，再尝试左侧。两侧都不足时，选择空间更大的一侧并贴边夹紧。
    static func x(anchorX: CGFloat, tooltipWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let width = max(tooltipWidth, 1)
        let rightEdge = anchorX + gap + width
        if rightEdge <= containerWidth - edgeInset {
            return anchorX + gap + width / 2
        }

        let leftEdge = anchorX - gap - width
        if leftEdge >= edgeInset {
            return anchorX - gap - width / 2
        }

        let rightSpace = containerWidth - edgeInset - (anchorX + gap)
        let leftSpace = anchorX - gap - edgeInset
        let preferred = rightSpace >= leftSpace
            ? anchorX + gap + width / 2
            : anchorX - gap - width / 2
        let minimum = edgeInset + width / 2
        let maximum = max(minimum, containerWidth - edgeInset - width / 2)
        return min(max(preferred, minimum), maximum)
    }

    static func y(anchorY: CGFloat, tooltipHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let halfHeight = max(tooltipHeight, 1) / 2
        let minimum = edgeInset + halfHeight
        let maximum = containerHeight - edgeInset - halfHeight
        guard maximum >= minimum else { return containerHeight / 2 }
        return min(max(anchorY, minimum), maximum)
    }
}

private struct ChartTooltip: View {
    let title: String
    let value: String
    let valueLabel: String
    let items: [ChartTooltipItem]

    init(title: String, value: String, valueLabel: String, items: [ChartTooltipItem] = []) {
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
                    .fill(PanelTheme.border)
                    .frame(height: 1)
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)
                            Text(item.label)
                                .font(.system(size: 9.5))
                                .foregroundStyle(PanelTheme.text2)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(item.value)
                                .font(.system(size: 9.5))
                                .fontDesign(.monospaced)
                                .foregroundStyle(PanelTheme.text)
                        }
                    }
                }
            } else {
                Text(valueLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(PanelTheme.text3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // 按内容自然收缩，避免 tooltip 变成一条横向色块。
        .fixedSize(horizontal: true, vertical: false)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ChartTooltipSizePreferenceKey.self, value: proxy.size)
            }
        }
        .background(PanelTheme.surface3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
        .shadow(color: PanelTheme.shadow, radius: 10, y: 4)
        .allowsHitTesting(false)
    }
}

// MARK: - 堆叠柱状图

private struct Sparkline: View {
    let values: [Double]
    let labels: [String]
    let color: Color
    @State private var hoveredIndex: Int?
    @State private var tooltipSize = CGSize(width: 128, height: 46)

    var body: some View {
        GeometryReader { proxy in
            let leadingInset: CGFloat = 44
            let trailingInset: CGFloat = 8
            let topInset: CGFloat = 7
            let bottomInset: CGFloat = 22
            let plotSize = CGSize(
                width: max(proxy.size.width - leadingInset - trailingInset, 1),
                height: max(proxy.size.height - topInset - bottomInset, 1)
            )
            let points = normalizedPoints(in: plotSize).map {
                CGPoint(x: $0.x + leadingInset, y: $0.y + topInset)
            }
            let peak = max(values.max() ?? 0, 1)

            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { index in
                    let ratio = CGFloat(index) / 3
                    let y = topInset + ratio * plotSize.height
                    let tickValue = Int(peak * (1 - Double(index) / 3))
                    Path { path in
                        path.move(to: CGPoint(x: leadingInset, y: y))
                        path.addLine(to: CGPoint(x: leadingInset + plotSize.width, y: y))
                    }
                    .stroke(PanelTheme.grid, lineWidth: 1)
                    Text(QuotaFormatters.tokensCN(tickValue))
                        .font(.system(size: 8))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text3)
                        .lineLimit(1)
                        .frame(width: leadingInset - 7, alignment: .trailing)
                        .position(x: (leadingInset - 7) / 2, y: y)
                }
                if points.count > 1 {
                    smoothPath(points, closeToBottom: topInset + plotSize.height)
                        .fill(color.opacity(0.12))
                    smoothPath(points)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(PanelTheme.surface)
                            .overlay(Circle().stroke(color, lineWidth: 2))
                            .frame(width: 7, height: 7)
                            .position(point)
                    }
                }
                ForEach(axisIndices, id: \.self) { index in
                    if labels.indices.contains(index), points.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: 8))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .fixedSize()
                            .position(x: points[index].x, y: topInset + plotSize.height + 13)
                    }
                }
                if let hoveredIndex,
                   values.indices.contains(hoveredIndex),
                   labels.indices.contains(hoveredIndex),
                   points.indices.contains(hoveredIndex) {
                    let point = points[hoveredIndex]
                    ChartTooltip(
                        title: labels[hoveredIndex],
                        value: QuotaFormatters.tokensCN(Int(values[hoveredIndex])),
                        valueLabel: "Token"
                    )
                    .position(
                        x: ChartTooltipPlacement.x(
                            anchorX: point.x,
                            tooltipWidth: tooltipSize.width,
                            containerWidth: proxy.size.width
                        ),
                        y: ChartTooltipPlacement.y(
                            anchorY: point.y,
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
                    hoveredIndex = index(at: location, plotWidth: plotSize.width, leadingInset: leadingInset)
                case .ended:
                    hoveredIndex = nil
                @unknown default:
                    hoveredIndex = nil
                }
            }
        }
    }

    private func index(at location: CGPoint, plotWidth: CGFloat, leadingInset: CGFloat) -> Int? {
        guard !values.isEmpty, plotWidth > 0 else { return nil }
        let x = min(max(location.x - leadingInset, 0), plotWidth)
        let ratio = x / plotWidth
        return min(max(Int((ratio * CGFloat(max(values.count - 1, 0))).rounded()), 0), values.count - 1)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxValue = max(values.max() ?? 0, 1)
        return values.enumerated().map { index, value in
            let x = values.count == 1 ? size.width / 2 : CGFloat(index) / CGFloat(values.count - 1) * size.width
            let y = size.height - CGFloat(value / maxValue) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private var axisIndices: [Int] {
        guard !values.isEmpty else { return [] }
        guard values.count > 4 else { return Array(values.indices) }
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
    let rows: [MainPanelView.DayRow]
    let claudeCodeLabel: String
    @State private var hoveredIndex: Int?
    @State private var tooltipSize = CGSize(width: 164, height: 142)

    var body: some View {
        GeometryReader { proxy in
            let peak = max(rows.map(\.total).max() ?? 1, 1)
            let plotHeight = max(proxy.size.height - 8, 1)
            let plotX: CGFloat = 40
            let plotWidth = max(proxy.size.width - 44, 1)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let plot = CGRect(x: plotX, y: 0, width: plotWidth, height: plotHeight)
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
                    let slotWidth = plot.width / CGFloat(rows.count)
                    let barWidth = min(22, max(slotWidth * 0.64, 0.65))
                    for (index, row) in rows.enumerated() {
                        let x = plot.minX + CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
                        var bottom = plot.maxY
                        let segments: [(Int, Color)] = [
                            (row.workbuddy, PanelTheme.workbuddy),
                            (row.claudeCode, PanelTheme.cclaude),
                            (row.claude, PanelTheme.claude),
                            (row.codex, PanelTheme.codex),
                        ]
                        for (value, color) in segments where value > 0 {
                            let height = max(CGFloat(value) / CGFloat(peak) * plot.height, min(1, plot.height))
                            let rect = CGRect(x: x, y: bottom - height, width: barWidth, height: height)
                            let radius = min(2, min(barWidth / 2, height / 2))
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: radius),
                                with: .color(color)
                            )
                            bottom -= height
                        }
                    }
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(QuotaFormatters.tokensCN(peak))
                    Spacer()
                    Text(QuotaFormatters.tokensCN(peak * 2 / 3))
                    Spacer()
                    Text(QuotaFormatters.tokensCN(peak / 3))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 8.5))
                .foregroundStyle(PanelTheme.text3)
                .frame(width: 32, height: plotHeight, alignment: .topTrailing)

                if let hoveredIndex, rows.indices.contains(hoveredIndex) {
                    let row = rows[hoveredIndex]
                    let slotWidth = plotWidth / CGFloat(max(rows.count, 1))
                    let barCenterX = plotX + CGFloat(hoveredIndex) * slotWidth + slotWidth / 2
                    let barTopY = plotHeight - CGFloat(row.total) / CGFloat(peak) * plotHeight
                    ChartTooltip(
                        title: row.isToday ? "今日" : row.label,
                        value: QuotaFormatters.tokensCN(row.total),
                        valueLabel: "Token",
                        items: [
                            ChartTooltipItem(label: "Codex", value: QuotaFormatters.tokensCN(row.codex), color: PanelTheme.codex),
                            ChartTooltipItem(label: "Claude", value: QuotaFormatters.tokensCN(row.claude), color: PanelTheme.claude),
                            ChartTooltipItem(label: claudeCodeLabel, value: QuotaFormatters.tokensCN(row.claudeCode), color: PanelTheme.cclaude),
                            ChartTooltipItem(label: "WorkBuddy", value: QuotaFormatters.tokensCN(row.workbuddy), color: PanelTheme.workbuddy)
                        ]
                    )
                    .position(
                        x: ChartTooltipPlacement.x(
                            anchorX: barCenterX,
                            tooltipWidth: tooltipSize.width,
                            containerWidth: proxy.size.width
                        ),
                        y: ChartTooltipPlacement.y(
                            anchorY: barTopY,
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
    @State private var hoveredIndex: Int?
    @State private var tooltipSize = CGSize(width: 128, height: 46)

    init(levels: [Int], values: [Int] = [], labels: [String] = [], leadingOffset: Int) {
        self.levels = levels
        self.values = values
        self.labels = labels
        self.leadingOffset = leadingOffset
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
                        value: QuotaFormatters.tokensCN(values[hoveredIndex]),
                        valueLabel: "Token"
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
