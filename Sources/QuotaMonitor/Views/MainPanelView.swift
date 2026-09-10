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

    /// 百分比卡阈值：≤30% 危急，≤50% 低余额。
    init(remainingPercent: Double?) {
        self.init(health: QuotaHealth(remaining: remainingPercent))
    }

    /// 余额卡阈值：≤2 天危急，≤7 天低余额。
    init(balanceAmount: Double?, days: Int?) {
        self.init(health: QuotaHealth(balanceAmount: balanceAmount, estimatedDays: days))
    }

    init(health: QuotaHealth) {
        switch health {
        case .healthy: self = .normal
        case .warning: self = .low
        case .critical: self = .critical
        case .unknown: self = .unknown
        }
    }

    var health: QuotaHealth {
        switch self {
        case .normal: .healthy
        case .low: .warning
        case .critical: .critical
        case .unknown: .unknown
        }
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
    @Bindable var appearanceSettings: AppearanceSettings
    @State private var loginItem = LoginItemManager()
    @State private var selectedPage: DashboardPage = .overview
    @State private var tokenPeriod: TokenPeriod = .sevenDays
    @State private var tokenChartDimension: TokenChartDimension = .platform
    @State private var hoveredPage: DashboardPage?
    @State private var showSourceHelp = false
    @State private var showCodexResetCreditsPopover = false
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
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
        // 数据来源与设置是故障恢复入口，任何数据状态下都必须可访问。
        guard selectedPage != .settings else { return false }
        return switch store.presentationSnapshot.availability {
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
                Text(QuotaMonitorIdentity.displayName)
                    .font(Font.custom("PingFang SC", size: 15.5).weight(.semibold))
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
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .frame(width: 15)
                            Text(language.text(page.titleKey))
                                .font(.system(size: 12, weight: selectedPage == page ? .semibold : .regular, design: .monospaced))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedPage == page ? PanelTheme.text : PanelTheme.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            selectedPage == page
                                ? PanelTheme.sidebarSelected
                                : (hoveredPage == page ? Color.primary.opacity(0.07) : .clear),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
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
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(PanelTheme.hairline)
                .frame(width: 1)
        }
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
            overviewRiskCard
            overviewHeroCard
            overviewQuotaGrid
            overviewBottomGrid
        }
    }

    /// 首页新增的唯一主状态，保留原有额度、Token 与排行模块顺序不变。
    private var overviewRiskCard: some View {
        let risk = OverviewRiskResolver.resolve(store: store)
        let isActionable = risk.actionPage != .overview
        let title = overviewRiskTitle(risk)
        let detail = overviewRiskDetail(risk)
        let color: Color = switch risk.level {
        case .healthy: PanelTheme.ok
        case .reminder: PanelTheme.warn
        case .critical: PanelTheme.danger
        case .trustWarning: PanelTheme.warn
        case .unavailable: PanelTheme.text2
        }
        let background: Color = switch risk.level {
        case .healthy: PanelTheme.okSoft
        case .reminder, .trustWarning: PanelTheme.warnSoft
        case .critical: PanelTheme.dangerSoft
        case .unavailable: PanelTheme.surface2
        }
        return Button {
            guard isActionable else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                selectedPage = .settings
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: risk.level == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    overviewRiskHeadline(risk, color: color)
                    overviewRiskDetailView(risk, color: color)
                }
                Spacer(minLength: 8)
                if isActionable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PanelTheme.text2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(detail). \(language.text("overview.risk.sourceSummary", readySourceCount, overviewFreshnessText))")
        .accessibilityHint(isActionable ? language.text("overview.risk.actionHint") : "")
    }

    @ViewBuilder
    private func overviewRiskHeadline(_ risk: OverviewRiskResolution, color: Color) -> some View {
        if let signal = risk.signal,
           signal.metric != .sharedBalance,
           let remaining = signal.remainingPercent,
           remaining > 0 {
            Text(language.text(
                "overview.risk.quota.remaining.prefix",
                overviewRiskProviderName(signal.provider),
                overviewRiskMetricName(signal.metric)
            ))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PanelTheme.text)
            + Text(QuotaFormatters.percent(remaining))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        } else {
            Text(overviewRiskTitle(risk))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PanelTheme.text)
        }
    }

    @ViewBuilder
    private func overviewRiskDetailView(_ risk: OverviewRiskResolution, color: Color) -> some View {
        if let reset = risk.signal?.resetsAt {
            Text(language.text(
                "overview.risk.resetDetail",
                QuotaFormatters.reset(reset, language: language.language),
                overviewRiskResetCountdown(reset)
            ))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
        } else {
            Text(overviewRiskDetail(risk))
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.text2)
                .lineLimit(2)
        }
    }

    private func overviewRiskResetCountdown(_ reset: Date) -> String {
        let countdown = QuotaFormatters.relativeReset(from: reset, language: language)
        guard language.language == .simplifiedChinese else { return countdown }
        return countdown.replacingOccurrences(of: " ", with: "")
    }

    private func overviewRiskTitle(_ risk: OverviewRiskResolution) -> String {
        guard let signal = risk.signal else {
            return language.text(risk.level == .trustWarning
                ? "overview.risk.trust.title"
                : "overview.risk.unavailable.title")
        }
        if signal.metric == .sharedBalance {
            if signal.balanceAmount.map({ $0 <= 0 }) == true {
                return language.text("overview.risk.balance.depleted", overviewRiskProviderName(signal.provider))
            }
            guard let days = signal.estimatedDays else {
                return language.text("overview.risk.unavailable.title")
            }
            return language.text("overview.risk.balance.days", overviewRiskProviderName(signal.provider), days)
        }
        let provider = overviewRiskProviderName(signal.provider)
        let metric = overviewRiskMetricName(signal.metric)
        if signal.remainingPercent == 0 {
            return language.text("overview.risk.quota.exhausted", provider, metric)
        }
        return language.text(
            "overview.risk.quota.remaining",
            provider,
            metric,
            QuotaFormatters.percent(signal.remainingPercent)
        )
    }

    private func overviewRiskDetail(_ risk: OverviewRiskResolution) -> String {
        var parts: [String] = []
        if let signal = risk.signal {
            if let reset = signal.resetsAt {
                parts.append(language.text(
                    "overview.risk.resetDetail",
                    QuotaFormatters.reset(reset, language: language.language),
                    overviewRiskResetCountdown(reset)
                ))
            } else if signal.metric == .sharedBalance {
                parts.append(language.text("overview.risk.balance.detail"))
            } else if signal.coverageRatio == nil {
                parts.append(language.text("overview.risk.thresholdFallback"))
            }
        } else {
            parts.append(language.text(risk.level == .trustWarning
                ? "overview.risk.trust.detail"
                : "overview.risk.unavailable.detail"))
        }
        if risk.unavailableQuotaSourceCount > 0, risk.signal != nil {
            parts.append(language.text("overview.risk.partialSources", risk.unavailableQuotaSourceCount))
        }
        return parts.joined(separator: " ")
    }

    private func overviewRiskProviderName(_ provider: OverviewRiskProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .deepSeek: "DeepSeek"
        }
    }

    private func overviewRiskMetricName(_ metric: OverviewRiskMetric) -> String {
        switch metric {
        case .session: language.text("panel.sessionLeft")
        case .weekly: language.text("overview.weekQuota")
        case .sharedBalance: language.text("overview.sharedBalance")
        }
    }

    private var readySourceCount: Int {
        store.dataSourceHealth.filter { $0.isInstalled && $0.state == .ready }.count
    }

    private var overviewFreshnessText: String {
        guard let date = store.latestUpdatedAt else { return "--" }
        return QuotaFormatters.clock(language: language.language).string(from: date)
    }

    private var overviewHeading: some View {
        Text(language.text("overview.pageTitle"))
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .kerning(-0.4)
            .foregroundStyle(PanelTheme.text)
    }

    /// 首页首卡只回答三个问题：今天用了多少、和昨天比如何、近7天的量级。
    private var overviewHeroCard: some View {
        let presentation = store.presentationSnapshot
        return panelCard(elevated: false) {
            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("menu.todayTokensLabel"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelTheme.text3)
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(QuotaFormatters.localizedTokens(presentation.today.total, language: language.language))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(heroYesterdayText)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(PanelTheme.text2)
                        if let delta = relativeDeltaText {
                            Text(delta)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .fontDesign(.monospaced)
                                .foregroundStyle(relativeDeltaColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(relativeDeltaColor.opacity(0.14), in: Capsule())
                                .fixedSize()
                        }
                    }
                }
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

    private var heroYesterdayText: String {
        let yesterday = store.yesterdayTokenUsage.map { QuotaFormatters.localizedTokens($0.total, language: language.language) } ?? "--"
        return language.text("overview.yesterdayComparison", yesterday)
    }

    private var todayPeakShare: String {
        let total = max(store.presentationSnapshot.lastSevenDays.total, 1)
        return String(format: "%.1f%%", Double(store.presentationSnapshot.today.total) / Double(total) * 100)
    }

    private func overviewHeroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.text3)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
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
        return String(format: "%@ %.1f%%", percent >= 0 ? "↑" : "↓", abs(percent))
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
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
        let facts: [OverviewQuotaFact]
        let state: BalanceState?

        var id: String { platform.rawValue }
    }

    private struct OverviewQuotaFact {
        let label: String
        let value: String
        let detail: String
        let health: QuotaHealth
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

    private var codexOverviewFacts: [OverviewQuotaFact] {
        if QuotaPresentationPolicy.mode(for: store.codexRoute) == .sharedBalance { return sharedOverviewFacts }
        return [
            quotaFact(label: language.text("panel.sessionLeft"), metric: .session, line: codexProvider?.session),
            quotaFact(label: language.text("overview.weekQuota"), metric: .weekly, line: codexProvider?.weekly)
        ]
    }

    private var claudeOverviewFacts: [OverviewQuotaFact] {
        if store.claudeUsesDeepSeek { return sharedOverviewFacts }
        let detail = store.claudeRouteSummary == .unknown
            ? language.text("settings.notConnected")
            : language.text("overview.quotaUnavailable")
        return [
            .init(label: language.text("overview.sessionQuota"), value: "--", detail: detail, health: .unknown),
            .init(label: language.text("overview.weekQuota"), value: "--", detail: detail, health: .unknown)
        ]
    }

    private var sharedOverviewFacts: [OverviewQuotaFact] {
        let health = QuotaHealth(balanceAmount: store.deepSeekBalance, estimatedDays: store.deepSeekDays)
        return [
            .init(label: language.text("overview.sharedBalance"), value: sharedBalanceText, detail: balanceStatusDetail(health), health: health),
            .init(label: language.text("overview.estimatedDays"), value: store.deepSeekDays.map { language.text("panel.daysShortLabel", "\($0)") } ?? "--", detail: language.text("overview.estimateNote"), health: health)
        ]
    }

    private func quotaFact(label: String, metric: OverviewRiskMetric, line: UsageLine?) -> OverviewQuotaFact {
        let health = codexQuotaHealth(metric: metric, line: line)
        return .init(
            label: label,
            value: line?.remainingPercent.map(QuotaFormatters.percent) ?? "--",
            detail: codexResetText(line),
            health: health
        )
    }

    private var codexOverviewState: BalanceState? {
        switch store.codexRoute {
        case .deepseek: BalanceState(balanceAmount: store.deepSeekBalance, days: store.deepSeekDays)
        case .official:
            codexOfficialRiskResolution.map { balanceState(for: $0.level) } ?? .unknown
        case .unknown: nil
        }
    }

    private var codexOfficialRiskResolution: OverviewRiskResolution? {
        guard let provider = codexProvider else { return nil }
        var candidates: [OverviewRiskCandidate] = []
        if let session = provider.session {
            candidates.append(.quota(provider: .codex, metric: .session, line: session))
        }
        if let weekly = provider.weekly {
            candidates.append(.quota(provider: .codex, metric: .weekly, line: weekly))
        }
        guard !candidates.isEmpty else { return nil }
        return OverviewRiskResolver.resolve(
            input: .init(
                candidates: candidates,
                unavailableQuotaSourceCount: 0,
                hasConnectedQuotaRoute: true
            ),
            now: .now
        )
    }

    private func codexQuotaHealth(metric: OverviewRiskMetric, line: UsageLine?) -> QuotaHealth {
        guard let line else { return .unknown }
        let resolution = OverviewRiskResolver.resolve(
            input: .init(
                candidates: [.quota(provider: .codex, metric: metric, line: line)],
                unavailableQuotaSourceCount: 0,
                hasConnectedQuotaRoute: true
            ),
            now: .now
        )
        return quotaHealth(for: resolution.level)
    }

    private func balanceState(for level: OverviewRiskLevel) -> BalanceState {
        switch level {
        case .healthy: .normal
        case .reminder: .low
        case .critical: .critical
        case .trustWarning, .unavailable: .unknown
        }
    }

    private func quotaHealth(for level: OverviewRiskLevel) -> QuotaHealth {
        balanceState(for: level).health
    }

    private var claudeOverviewState: BalanceState? {
        if store.claudeUsesDeepSeek { return BalanceState(balanceAmount: store.deepSeekBalance, days: store.deepSeekDays) }
        return switch store.claudeRouteSummary {
        case .official, .other, .mixed: BalanceState.unknown
        case .deepseek: BalanceState(balanceAmount: store.deepSeekBalance, days: store.deepSeekDays)
        case .unknown: nil
        }
    }

    private func codexResetText(_ line: UsageLine?) -> String {
        guard let line else { return language.text("overview.noResetData") }
        guard let reset = line.resetsAt else { return language.text("overview.noResetData") }
        return language.text("overview.resetAfter", QuotaFormatters.reset(reset, language: language.language))
    }

    private func balanceStatusDetail(_ health: QuotaHealth) -> String {
        let status = switch health {
        case .healthy: language.text("quota.status.healthy")
        case .warning: language.text("quota.status.warning")
        case .critical: language.text("quota.status.critical")
        case .unknown: language.text("quota.status.pendingEstimate")
        }
        return "\(status) · \(language.text("overview.balanceNoReset"))"
    }

    private func overviewQuotaCard(
        icon: BrandIconKind,
        name: String,
        route: String,
        facts: [OverviewQuotaFact],
        state: BalanceState?
    ) -> some View {
        let status = overviewStatus(for: state)
        return panelCard {
            HStack(spacing: 8) {
                BrandIconView(kind: icon, size: icon == .codex ? 22 : 18)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PanelTheme.text)
                    HStack(spacing: 5) {
                        Text(route)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                        if icon == .codex,
                           let resetCredits = store.codexResetCredits,
                           resetCredits.availableCount > 0 {
                            codexResetCreditsInline(resetCredits)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(status.label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(status.background, in: Capsule())
            }
            HStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.label)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                        Text(fact.value)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.quotaValueColor(fact.health))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(fact.detail)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
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

    private func codexResetCreditsInline(_ resetCredits: CodexResetCredits) -> some View {
        let label = language.text("overview.resetCredits.inline", resetCredits.availableCount)
        let help = codexResetCreditsHelp(resetCredits)
        return HStack(spacing: 3) {
            (
                Text(language.text("overview.resetCredits.inline.prefix"))
                    .foregroundStyle(PanelTheme.text2)
                + Text(language.text("overview.resetCredits.inline.value", resetCredits.availableCount))
                    .foregroundStyle(PanelTheme.chartAccent)
                + Text(language.text("overview.resetCredits.inline.suffix"))
                    .foregroundStyle(PanelTheme.text2)
            )
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
            Button {
                showCodexResetCreditsPopover.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PanelTheme.text3)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCodexResetCreditsPopover, arrowEdge: .bottom) {
                codexResetCreditsPopover(resetCredits)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(help)
            .accessibilityHint(language.text("overview.resetCredits.clickHint"))
        }
        .accessibilityElement(children: .contain)
    }

    private func codexResetCreditsPopover(_ resetCredits: CodexResetCredits) -> some View {
        let missingCount = max(resetCredits.availableCount - resetCredits.expirations.count, 0)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                Text(language.text("overview.resetCredits.title.prefix"))
                    .foregroundStyle(PanelTheme.text)
                Text(language.text("overview.resetCredits.title.value", resetCredits.availableCount))
                    .foregroundStyle(PanelTheme.chartAccent)
                Text(language.text("overview.resetCredits.title.suffix"))
                    .foregroundStyle(PanelTheme.text)
            }
            .font(.system(size: 12, weight: .semibold))
            ForEach(Array(resetCredits.expirations.enumerated()), id: \.offset) { index, expiration in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(language.text("overview.resetCredits.item", index + 1))
                        .foregroundStyle(PanelTheme.text2)
                    Spacer(minLength: 12)
                    HStack(spacing: 0) {
                        Text(language.text("overview.resetCredits.expiresAt.prefix"))
                            .foregroundStyle(PanelTheme.text3)
                        Text(QuotaFormatters.reset(expiration, language: language.language))
                            .foregroundStyle(PanelTheme.chartAccent)
                        Text(language.text("overview.resetCredits.expiresAt.suffix"))
                            .foregroundStyle(PanelTheme.text3)
                    }
                    .fontDesign(.monospaced)
                }
                .font(.system(size: 10))
            }
            if missingCount > 0 {
                Text(language.text("overview.resetCredits.missingExpirations", missingCount))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.text2)
            }
            if resetCredits.expirations.isEmpty, missingCount == 0 {
                Text(language.text("overview.resetCredits.noExpirations"))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.text2)
            }
        }
        .padding(12)
        .frame(minWidth: 228)
        .background(PanelTheme.tooltipSurface)
    }

    private func codexResetCreditsHelp(_ resetCredits: CodexResetCredits) -> String {
        var lines = [language.text("overview.resetCredits.title", resetCredits.availableCount)]
        lines.append(contentsOf: resetCredits.expirations.enumerated().map { index, expiration in
            language.text(
                "overview.resetCredits.helpRow",
                index + 1,
                QuotaFormatters.reset(expiration, language: language.language)
            )
        })
        let missingCount = max(resetCredits.availableCount - resetCredits.expirations.count, 0)
        if missingCount > 0 {
            lines.append(language.text("overview.resetCredits.missingExpirations", missingCount))
        }
        if resetCredits.expirations.isEmpty, missingCount == 0 {
            lines.append(language.text("overview.resetCredits.noExpirations"))
        }
        return lines.joined(separator: "\n")
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
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
                let plotWidth = max(proxy.size.width - 52, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(axisIndices, id: \.self) { index in
                        let row = chart.rows[index]
                        let x = 44 + (CGFloat(index) + 0.5) / CGFloat(max(chart.rows.count, 1)) * plotWidth
                        // 横轴只显示开始时间；完整区间（开始-结束）见 hover 数据标签
                        Text(String(row.label.prefix(5)))
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
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
        // 与 Token 看板柱状图、下拉框行共用同一索引映射（见 UsageBreakdownColor）。
        UsageBreakdownColor.color(for: key)
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("panel.today"))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
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
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(PanelTheme.text)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(QuotaFormatters.localizedTokens(item.value, language: language.language))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(height: rowHeight)
                }
                if values.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10, design: .monospaced))
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
                .font(.system(size: 22, weight: .bold, design: .monospaced))
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
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricCell(_ label: String, _ value: String, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.text3)
            Text(value)
                .font(.system(size: large ? 21 : 16, weight: .semibold, design: .monospaced))
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer(minLength: 6)
                Text(language.text("tokens.peakValue", QuotaFormatters.localizedTokens(chart.rows.map { $0.total }.max() ?? 0, language: language.language)))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text3)
                tokenChartDimensionPicker
            }
            StackedBarChart(
                rows: chart.rows,
                todayLabel: language.text("panel.today"),
                tokenLabel: language.text("panel.totalTokens"),
                language: language.language,
                showsSingleSegmentBreakdown: true
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
                    let x = 44 + (CGFloat(index) + 0.5) / CGFloat(max(chart.rows.count, 1)) * plotWidth
                    Text(row.isToday ? language.text("panel.today") : row.label)
                        .font(.system(size: 8.5, weight: row.isToday ? .semibold : .regular, design: .monospaced))
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
                    .font(.system(size: 10, design: .monospaced))
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 5) {
                ForEach(items.prefix(5)) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 10, design: .monospaced))
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
                            .font(.system(size: 9, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                            .frame(width: 54, alignment: .trailing)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(height: 17)
                }
                if items.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10, design: .monospaced))
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                HStack(spacing: 4) {
                    Text(language.text("tokens.less"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(heatColor(level: level))
                            .frame(width: 9, height: 9)
                    }
                    Text(language.text("tokens.more"))
                        .font(.system(size: 9, design: .monospaced))
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
                        .font(.system(size: 8.5, design: .monospaced))
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
                            .font(.system(size: 8, design: .monospaced))
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
        case 1: PanelTheme.heat1
        case 2: PanelTheme.heat2
        case 3: PanelTheme.heat3
        case 4: PanelTheme.heat4
        default: PanelTheme.heat0
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("settings.title"))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .kerning(-0.4)
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 14) {
                settingsCard {
                    settingsRow(title: language.text("settings.launchAtLogin"), detail: language.text("settings.launchAtLogin.detail")) {
                        Toggle("", isOn: Binding(
                            get: { loginItem.isRegistered },
                            set: { loginItem.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(PanelTheme.chartAccent)
                        .accessibilityLabel(language.text("settings.launchAtLogin"))
                        .accessibilityHint(language.text("settings.launchAtLogin.hint"))
                    }
                    settingsRow(title: language.text("settings.language"), detail: language.text("settings.language.detail")) {
                        PanelSegmentedControl(
                            options: AppLanguage.allCases,
                            selection: $language.language
                        ) { value in
                            value == .simplifiedChinese ? "简体中文" : "English"
                        }
                    }
                    settingsRow(title: language.text("settings.appearance"), detail: language.text("settings.appearance.detail")) {
                        PanelSegmentedControl(
                            options: AppearanceMode.allCases,
                            selection: $appearanceSettings.mode
                        ) { mode in
                            switch mode {
                            case .system: language.text("appearance.system")
                            case .light: language.text("appearance.light")
                            case .dark: language.text("appearance.dark")
                            }
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
            trustedSourcesCard
        }
    }

    private var trustedSourcesCard: some View {
        settingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("settings.sources"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelTheme.text)
                    Text(language.text("settings.sources.detail"))
                        .font(.system(size: 10))
                        .foregroundStyle(PanelTheme.text2)
                }
                Spacer(minLength: 8)
                Text(language.text("settings.sources.summary", trustedSources.filter { $0.state == .ready }.count, trustedSources.filter { $0.state != .ready }.count))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(PanelTheme.text2)
                    .lineLimit(1)
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label(language.text("settings.sources.rescan"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(language.text("settings.sources.rescan.hint"))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            sourceCapabilityTable
            if showSourceHelp {
                Text(language.text("settings.sources.help"))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.bottom, 12)
            }
        }
    }

    private struct SourceCapabilityRow: Identifiable {
        let id: String
        let product: String
        let quotaSources: [DataSourceHealthSnapshot]
        let tokenSources: [DataSourceHealthSnapshot]

        var isInstalled: Bool {
            quotaSources.contains(where: \.isInstalled) || tokenSources.contains(where: \.isInstalled)
        }

        var canReadQuota: Bool {
            quotaSources.contains { $0.state == .ready }
        }

        var canReadToken: Bool {
            tokenSources.contains { $0.state == .ready }
        }

        var sourceDetails: [DataSourceHealthSnapshot] {
            var seen = Set<DataSourceID>()
            return (quotaSources + tokenSources).filter { seen.insert($0.id).inserted }
        }

        var redactedPaths: String {
            sourceDetails.map(\.redactedPath).joined(separator: " · ")
        }

        var validRecordCount: Int {
            sourceDetails.reduce(0) { $0 + $1.validRecordCount }
        }

    }

    private var trustedSources: [DataSourceHealthSnapshot] {
        store.dataSourceHealth.filter(\.isInstalled)
    }

    private var sourceCapabilityRows: [SourceCapabilityRow] {
        let sources = store.dataSourceHealth
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var rows: [SourceCapabilityRow] = []
        func source(_ id: DataSourceID) -> DataSourceHealthSnapshot? { byID[id] }
        func append(_ id: String, _ product: String, quota: [DataSourceHealthSnapshot], token: [DataSourceHealthSnapshot]) {
            let row = SourceCapabilityRow(id: id, product: product, quotaSources: quota, tokenSources: token)
            if row.isInstalled { rows.append(row) }
        }

        append(
            "codex",
            language.text("settings.sources.codexProduct"),
            quota: [source(DataSourceCatalog.codexQuota)].compactMap { $0 },
            token: [source(DataSourceCatalog.codexToken)].compactMap { $0 }
        )
        append(
            "deepseek",
            language.text("settings.sources.deepseekProduct"),
            quota: [source(DataSourceCatalog.deepSeekBalance)].compactMap { $0 },
            token: []
        )
        append(
            "claude",
            language.text("settings.sources.claudeProduct"),
            quota: store.claudeUsesDeepSeek ? [source(DataSourceCatalog.deepSeekBalance)].compactMap { $0 } : [],
            token: [source(DataSourceCatalog.claudeCode), source(DataSourceCatalog.claudeDesktop)].compactMap { $0 }
        )
        append(
            "workbuddy",
            language.text("settings.sources.workbuddyProduct"),
            quota: [],
            token: [source(DataSourceCatalog.workBuddy)].compactMap { $0 }
        )
        append(
            "qoder",
            language.text("settings.sources.qoderProduct"),
            quota: [],
            token: [source(DataSourceCatalog.qoder)].compactMap { $0 }
        )
        let builtInPlatforms: Set<String> = ["codex", "deepseek", "claude", "workbuddy", "qoder"]
        let additional = sources.filter {
            !builtInPlatforms.contains($0.id.platform) && $0.kind == .localToken && $0.isInstalled
        }
        let additionalPlatforms = Set(additional.map { $0.id.platform }).sorted()
        for platform in additionalPlatforms {
            let matching = additional.filter { $0.id.platform == platform }
            append(platform, matching.first?.fallbackName ?? platform.capitalized, quota: [], token: matching)
        }
        return rows
    }

    private var sourceCapabilityTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(language.text("settings.sources.table.product"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(language.text("settings.sources.table.quota"))
                    .frame(width: 72, alignment: .center)
                Text(language.text("settings.sources.table.token"))
                    .frame(width: 72, alignment: .center)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PanelTheme.text2)
            .padding(.horizontal, 15)
            .padding(.bottom, 6)

            ForEach(sourceCapabilityRows) { row in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.product)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PanelTheme.text)
                        Text(row.redactedPaths)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                            .lineLimit(2)
                        if row.validRecordCount > 0 {
                            Text(language.text("settings.sources.table.records", row.validRecordCount))
                                .font(.system(size: 9))
                                .foregroundStyle(PanelTheme.text3)
                        }
                        let quotaReason = capabilityReason(for: row.quotaSources, labelKey: "settings.sources.table.quota")
                        let tokenReason = capabilityReason(for: row.tokenSources, labelKey: "settings.sources.table.token")
                        if let quotaReason, let tokenReason {
                            Text("\(quotaReason) · \(tokenReason)")
                                .font(.system(size: 9))
                                .foregroundStyle(PanelTheme.danger)
                                .lineLimit(2)
                        } else if let quotaReason {
                            Text(quotaReason)
                                .font(.system(size: 9))
                                .foregroundStyle(PanelTheme.danger)
                                .lineLimit(2)
                        } else if let tokenReason {
                            Text(tokenReason)
                                .font(.system(size: 9))
                                .foregroundStyle(PanelTheme.danger)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    capabilityCell(isAvailable: row.canReadQuota, label: language.text("settings.sources.table.quota"))
                        .frame(width: 72)
                    capabilityCell(isAvailable: row.canReadToken, label: language.text("settings.sources.table.token"))
                        .frame(width: 72)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PanelTheme.separator).frame(height: 0.5).padding(.horizontal, 15)
                }
            }

            if sourceCapabilityRows.isEmpty {
                Text(language.text("settings.sources.table.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
            }

            Spacer(minLength: 0)
        }
    }

    private func capabilityCell(isAvailable: Bool, label: String) -> some View {
        Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isAvailable ? PanelTheme.success : PanelTheme.danger)
            .accessibilityLabel("\(label): \(language.text(isAvailable ? "settings.sources.table.available" : "settings.sources.table.unavailable"))")
    }

    private func capabilityReason(for sources: [DataSourceHealthSnapshot], labelKey: String) -> String? {
        guard !sources.contains(where: { $0.state == .ready }) else { return nil }
        let reasonKey: String
        guard let state = sourceReasonState(for: sources) else {
            reasonKey = "settings.sources.table.reason.noSource"
            return language.text("settings.sources.table.reason", language.text(labelKey), language.text(reasonKey))
        }
        reasonKey = switch state {
        case .noData: "settings.sources.table.reason.noData"
        case .notDetected: "settings.sources.table.reason.notDetected"
        case .needsPermission: "settings.sources.table.reason.permission"
        case .unsupportedFormat: "settings.sources.table.reason.unsupported"
        case .failed: "settings.sources.table.reason.failed"
        case .stale: "settings.sources.table.reason.stale"
        case .scanning: "settings.sources.table.reason.scanning"
        case .ready: "settings.sources.table.reason.noSource"
        }
        return language.text("settings.sources.table.reason", language.text(labelKey), language.text(reasonKey))
    }

    private func sourceReasonState(for sources: [DataSourceHealthSnapshot]) -> DataSourceHealthState? {
        let priority: [DataSourceHealthState] = [.needsPermission, .failed, .unsupportedFormat, .stale, .noData, .notDetected, .scanning]
        return priority.first { state in sources.contains { $0.state == state } }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func settingsRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
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
                    color: PanelTheme.chartPrimary
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
        let palette = PanelTheme.categoryPalette
        return Dictionary(
            categories.map { category in
                (category.id, palette[category.preferredPaletteIndex % palette.count])
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func stablePaletteIndex(for value: String) -> Int {
        UsageBreakdownColor.stableIndex(for: value)
    }

    private func stableCategoryColor(for value: String) -> Color {
        PanelTheme.categoryPalette[stablePaletteIndex(for: value)]
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
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(PanelTheme.text)
                            Text(loadingProgressText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(PanelTheme.text2)
                        }
                        Spacer()
                        if let progress = store.localTokenRefreshProgress {
                            Text("\(Int(progress.fraction * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                        .font(.system(size: 30, weight: .medium, design: .monospaced))
                        .foregroundStyle(PanelTheme.codex)
                    Text(language.text("panel.noDataTitle"))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(PanelTheme.text)
                    Text(language.text("panel.noDataDetail"))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
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
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(PanelTheme.surface)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .opacity(reduceMotion ? 0.72 : 0.88)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PanelTheme.danger)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.text2)
            Spacer(minLength: 8)
            Text(language.text("panel.showingLastData"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelTheme.text3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(PanelTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                .font(.system(size: 9, weight: .regular, design: .monospaced))
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
        elevated: Bool = true,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 16)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(elevated ? PanelTheme.surfaceFloat : PanelTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if elevated {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(PanelTheme.border, lineWidth: 0.5)
            }
        }
        .shadow(
            color: elevated ? Color.black.opacity(0.08) : .clear,
            radius: elevated ? 16 : 0,
            y: elevated ? 4 : 0
        )
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
                .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                            Capsule()
                                .fill(PanelTheme.surface)
                                .frame(width: PanelSegmentedMetrics.segmentWidth, height: PanelSegmentedMetrics.height)
                                .shadow(color: PanelTheme.shadowSmall, radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selection", in: selectionIndicator)
                        }
                        Text(label(option))
                            .font(.system(size: 11, weight: selection == option ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(
                                enabled
                                    ? (selection == option ? PanelTheme.text : PanelTheme.text2)
                                    : PanelTheme.text3
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: PanelSegmentedMetrics.segmentWidth, height: PanelSegmentedMetrics.height)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(enabled ? "" : (disabledHelp?(option) ?? ""))
            }
        }
        .padding(2)
        .background(PanelTheme.surface2, in: Capsule())
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

private struct ChartTooltipLayout: Layout {
    // Measure the rendered SwiftUI content instead of estimating text widths
    // with AppKit fonts. This keeps the tooltip adaptive while ensuring that
    // labels are truncated only when the real content exceeds the 350pt cap.
    static let minimumWidth: CGFloat = 140
    static let maximumWidth: CGFloat = 350
    static let initialSize = CGSize(width: minimumWidth, height: 46)

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let idealSize = content.sizeThatFits(.unspecified)
        let width = min(max(ceil(idealSize.width), Self.minimumWidth), Self.maximumWidth)
        let fittedSize = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: ceil(fittedSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let content = subviews.first else { return }
        content.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
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
        ChartTooltipLayout {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text2)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(value)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if !items.isEmpty {
                    Rectangle()
                        .fill(PanelTheme.separator)
                        .frame(height: 1)
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            HStack(alignment: .center, spacing: 6) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(PanelTheme.text2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                Spacer(minLength: 4)
                                Text(item.value)
                                    .font(.system(size: 9, design: .monospaced))
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(PanelTheme.text)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                } else if let valueLabel {
                    Text(valueLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ChartTooltipSizePreferenceKey.self, value: proxy.size)
            }
        }
        // 浮动浮层：浮卡面 + 描边 + 投影（规范允许投影的浮动产品组件）。
        // tooltipSurface / tooltipBorder 在深色模式下比卡片提亮一档，保证与画布区分。
        .background(PanelTheme.tooltipSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PanelTheme.tooltipBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
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
    @State private var isSelectionPinned = false

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
                .font(.system(size: 8.5, design: .monospaced))
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
                            .font(.system(size: 8.5, design: .monospaced))
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
            .focusable()
            .focusEffectDisabled()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language == .simplifiedChinese ? "Token 趋势图" : "Token trend chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction { direction in
                moveSelection(direction == .increment ? 1 : -1)
            }
            .onKeyPress(.return) {
                toggleSelection()
                return .handled
            }
            .onKeyPress(.space) {
                toggleSelection()
                return .handled
            }
            .onMoveCommand { direction in
                switch direction {
                case .left: moveSelection(-1)
                case .right: moveSelection(1)
                default: break
                }
            }
            .onExitCommand { hoveredIndex = nil; isSelectionPinned = false }
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    if !isSelectionPinned {
                        hoveredIndex = index(at: location, plotX: plotX, plotWidth: plotWidth)
                    }
                case .ended:
                    if !isSelectionPinned { hoveredIndex = nil }
                @unknown default:
                    if !isSelectionPinned { hoveredIndex = nil }
                }
            }
        }
    }

    private func index(at location: CGPoint, plotX: CGFloat, plotWidth: CGFloat) -> Int? {
        guard !values.isEmpty, location.x >= plotX, location.x <= plotX + plotWidth else { return nil }
        let slotWidth = plotWidth / CGFloat(values.count)
        return min(max(Int((location.x - plotX) / slotWidth), 0), values.count - 1)
    }

    private var accessibilitySummary: String {
        guard let index = hoveredIndex, values.indices.contains(index), labels.indices.contains(index) else {
            return language == .simplifiedChinese ? "聚焦后按左右键查看每日 Token，按 Enter 或空格固定选择" : "Focus the chart, use left or right arrows to inspect each day, then press Enter or Space to pin the selection"
        }
        let pinned = isSelectionPinned ? (language == .simplifiedChinese ? "，已固定" : ", pinned") : ""
        return "\(labels[index]), \(QuotaFormatters.localizedTokens(Int(values[index]), language: language))\(pinned)"
    }

    private func moveSelection(_ delta: Int) {
        guard !values.isEmpty else { return }
        let current = hoveredIndex ?? (delta > 0 ? -1 : values.count)
        hoveredIndex = max(0, min(values.count - 1, current + delta))
    }

    private func toggleSelection() {
        guard !values.isEmpty else { return }
        if hoveredIndex == nil { hoveredIndex = 0 }
        isSelectionPinned.toggle()
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
    @State private var isSelectionPinned = false

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
            let plotX: CGFloat = 44
            let plotWidth = max(proxy.size.width - 52, 1)
            let slotWidth = plotWidth / CGFloat(max(rows.count, 1))
            let barWidth = min(20, max(slotWidth * 0.6, 0.65))
            let plot = CGRect(x: plotX, y: plotTopInset, width: plotWidth, height: plotHeight)
            let barGeometries = rows.enumerated().map { index, row in
                let slotX = plot.minX + CGFloat(index) * slotWidth
                return StackedBarGeometry.make(
                    values: row.segments.map(\.value),
                    peak: peak,
                    plot: plot,
                    barX: slotX + (slotWidth - barWidth) / 2,
                    barWidth: barWidth,
                    hoverX: slotX + 2,
                    hoverWidth: slotWidth - 4
                )
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
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
                        let geometry = barGeometries[index]
                        for (segmentIndex, segment) in row.segments.enumerated() {
                            let rect = geometry.segmentRects[segmentIndex]
                            guard rect.height > 0 else { continue }
                            let isEmphasized = hoveredIndex == nil || hoveredIndex == index
                            let color = segment.color.opacity(isEmphasized ? 1 : 0.42)
                            let radius = min(2, min(barWidth / 2, rect.height / 2))
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: radius),
                                with: .color(color)
                            )
                            var separator = Path()
                            separator.move(to: CGPoint(x: rect.minX, y: rect.minY))
                            separator.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                            context.stroke(separator, with: .color(PanelTheme.surface.opacity(0.78)), lineWidth: 0.75)
                        }
                        if hoveredIndex == index {
                            context.stroke(
                                Path(roundedRect: geometry.barRect, cornerRadius: min(2, barWidth / 2)),
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
                .font(.system(size: 8.5, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text3)
                .frame(width: 32, height: plotHeight, alignment: .topTrailing)
                .position(x: 16, y: plotTopInset + plotHeight / 2)

                if let hoveredIndex, rows.indices.contains(hoveredIndex) {
                    let row = rows[hoveredIndex]
                    let detailSegments = row.segments.filter { $0.name != tokenLabel }
                    let tooltipItems = (detailSegments.count > 1 || showsSingleSegmentBreakdown)
                        ? compactTooltipItems(detailSegments)
                        : []
                    let tooltipCenter = ChartTooltipPlacement.adjacentToBar(
                        barRect: barGeometries[hoveredIndex].barRect,
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
            .focusable()
            .focusEffectDisabled()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language == .simplifiedChinese ? "Token 趋势图" : "Token trend chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction { direction in
                moveSelection(direction == .increment ? 1 : -1)
            }
            .onKeyPress(.return) {
                toggleSelection()
                return .handled
            }
            .onKeyPress(.space) {
                toggleSelection()
                return .handled
            }
            .onMoveCommand { direction in
                switch direction {
                case .left: moveSelection(-1)
                case .right: moveSelection(1)
                default: break
                }
            }
            .onExitCommand { hoveredIndex = nil; isSelectionPinned = false }
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    if !isSelectionPinned {
                        hoveredIndex = index(at: location, plotX: plotX, plotWidth: plotWidth)
                    }
                case .ended:
                    if !isSelectionPinned { hoveredIndex = nil }
                @unknown default:
                    if !isSelectionPinned { hoveredIndex = nil }
                }
            }
        }
    }

    private func compactTooltipItems(
        _ segments: [MainPanelView.TokenChartSegment]
    ) -> [ChartTooltipItem] {
        let colors = Dictionary(
            segments.map { ($0.id, $0.color) },
            uniquingKeysWith: { first, _ in first }
        )
        return ChartTooltipBreakdown.compact(
            segments.map {
                ChartTooltipBreakdownEntry(id: $0.id, label: $0.name, value: $0.value)
            }
        ).map { entry in
            ChartTooltipItem(
                label: entry.hiddenItemCount > 0
                    ? otherItemsLabel(entry.hiddenItemCount)
                    : entry.label,
                value: QuotaFormatters.localizedTokens(entry.value, language: language),
                color: entry.hiddenItemCount > 0
                    ? PanelTheme.chartDim
                    : (colors[entry.id] ?? PanelTheme.chartDim)
            )
        }
    }

    private func otherItemsLabel(_ count: Int) -> String {
        language == .simplifiedChinese ? "其他 \(count) 项" : "\(count) other items"
    }

    private var accessibilitySummary: String {
        guard let index = hoveredIndex, rows.indices.contains(index) else {
            return language == .simplifiedChinese ? "聚焦后按左右键查看每日 Token，按 Enter 或空格固定选择" : "Focus the chart, use left or right arrows to inspect each day, then press Enter or Space to pin the selection"
        }
        let row = rows[index]
        let details = row.segments
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { "\($0.name) \(QuotaFormatters.localizedTokens($0.value, language: language))" }
            .joined(separator: " · ")
        let detailText = details.isEmpty ? "" : (language == .simplifiedChinese ? "，分类：\(details)" : ", categories: \(details)")
        let pinned = isSelectionPinned ? (language == .simplifiedChinese ? "，已固定" : ", pinned") : ""
        return "\(row.label), \(QuotaFormatters.localizedTokens(row.total, language: language))\(detailText)\(pinned)"
    }

    private func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let current = hoveredIndex ?? (delta > 0 ? -1 : rows.count)
        hoveredIndex = max(0, min(rows.count - 1, current + delta))
    }

    private func toggleSelection() {
        guard !rows.isEmpty else { return }
        if hoveredIndex == nil { hoveredIndex = 0 }
        isSelectionPinned.toggle()
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
    @State private var isSelectionPinned = false

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
            .focusable()
            .focusEffectDisabled()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language == .simplifiedChinese ? "年度 Token 热力图" : "Yearly token heatmap")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction { direction in
                moveSelection(direction == .increment ? 1 : -1)
            }
            .onKeyPress(.return) {
                toggleSelection()
                return .handled
            }
            .onKeyPress(.space) {
                toggleSelection()
                return .handled
            }
            .onMoveCommand { direction in
                switch direction {
                case .left: moveSelection(-1)
                case .right: moveSelection(1)
                default: break
                }
            }
            .onExitCommand { hoveredIndex = nil; isSelectionPinned = false }
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    if !isSelectionPinned {
                        hoveredIndex = index(at: location, metrics: metrics)
                    }
                case .ended:
                    if !isSelectionPinned { hoveredIndex = nil }
                @unknown default:
                    if !isSelectionPinned { hoveredIndex = nil }
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

    private var accessibilitySummary: String {
        guard let index = hoveredIndex, values.indices.contains(index), labels.indices.contains(index) else {
            return language == .simplifiedChinese ? "聚焦后按左右键查看每日 Token，按 Enter 或空格固定选择" : "Focus the heatmap, use left or right arrows to inspect each day, then press Enter or Space to pin the selection"
        }
        let pinned = isSelectionPinned ? (language == .simplifiedChinese ? "，已固定" : ", pinned") : ""
        return "\(labels[index]), \(QuotaFormatters.localizedTokens(values[index], language: language))\(pinned)"
    }

    private func moveSelection(_ delta: Int) {
        guard !values.isEmpty else { return }
        let current = hoveredIndex ?? (delta > 0 ? -1 : values.count)
        hoveredIndex = max(0, min(values.count - 1, current + delta))
    }

    private func toggleSelection() {
        guard !values.isEmpty else { return }
        if hoveredIndex == nil { hoveredIndex = 0 }
        isSelectionPinned.toggle()
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1: PanelTheme.heat1
        case 2: PanelTheme.heat2
        case 3: PanelTheme.heat3
        case 4: PanelTheme.heat4
        default: PanelTheme.heat0
        }
    }
}
