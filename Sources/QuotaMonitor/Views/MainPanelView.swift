import AppKit
import SwiftUI

extension Notification.Name {
    static let quotaMonitorOpenSettings = Notification.Name("QuotaMonitor.openSettings")
    static let quotaMonitorToggleZoom = Notification.Name("QuotaMonitor.toggleZoom")
    static let quotaMonitorOpenReminder = Notification.Name("QuotaMonitor.openReminder")
}

/// 只让主面板右侧顶部横条响应窗口拖拽，避免正文空白区域误拖动窗口。
private final class PanelTitlebarDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            NotificationCenter.default.post(name: .quotaMonitorToggleZoom, object: nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

private struct PanelTitlebarDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelTitlebarDragNSView {
        PanelTitlebarDragNSView()
    }

    func updateNSView(_ nsView: PanelTitlebarDragNSView, context: Context) {}
}

// MARK: - 余额状态

enum BalanceState {
    case normal
    case low
    case critical
    case unknown

    /// 百分比卡与提醒共用固定阈值：≤5% 高风险，≤30% 需关注。
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

}

enum MainPanelLayout {
    static let sidebarWidth: CGFloat = 210
    static let sidebarLeadingInset: CGFloat = 16
}

enum DashboardPage: String, CaseIterable {
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

enum TokenPeriod: String, CaseIterable, Identifiable {
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

enum TokenChartDimension: String, CaseIterable, Identifiable {
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
    @Bindable var reminderSettings: ReminderSettings
    @State var loginItem = LoginItemManager()
    @State var selectedPage: DashboardPage = .overview
    @State var tokenPeriod: TokenPeriod = .sevenDays
    @State var tokenChartDimension: TokenChartDimension = .platform
    @State var hoveredPage: DashboardPage?
    @State var showSourceHelp = false
    @State var showCodexResetCreditsPopover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

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
            .background(PanelTheme.background)
        }
        .frame(minWidth: 820, minHeight: 540)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .quotaMonitorOpenSettings)) { _ in
            selectPage(.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaMonitorOpenReminder)) { notification in
            let destination = (notification.object as? String).flatMap(ReminderDestination.init(rawValue:)) ?? .overview
            selectPage(destination == .tokens ? .tokens : .overview)
        }
    }

    var titlebar: some View {
        ZStack {
            PanelTitlebarDragSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(QuotaMonitorIdentity.displayName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelTheme.text2)
                // 标题栏属于右侧内容列，但标题视觉中心要落在整个窗口中心。
                .offset(x: -MainPanelLayout.sidebarWidth / 2, y: -2)
                .allowsHitTesting(false)
            HStack {
                Spacer()
                TitlebarStatusView(store: store, language: language)
                    .padding(.trailing, 12)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 38)
        // 顶部属于右侧正文列，使用与正文完全一致的实色画布。
        .background(PanelTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PanelTheme.separator)
                .frame(height: 0.5)
        }
    }

    var panelBody: some View {
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

    var shouldShowEmptyState: Bool {
        // 数据来源与设置是故障恢复入口，任何数据状态下都必须可访问。
        guard selectedPage != .settings else { return false }
        return switch store.presentationSnapshot.availability {
        case .loading, .unavailable, .error: true
        case .ready, .connectedOnly, .stale: false
        }
    }

    var pageTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(x: 5))
    }

    func selectPage(_ page: DashboardPage) {
        guard selectedPage != page else { return }
        if page == .settings {
            // 设置页包含已开启的原生开关。禁用这一次页面切换动画，避免开关
            // 在插入视图时从“关闭”补间到真实状态，造成状态被修改的错觉。
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { selectedPage = page }
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                selectedPage = page
            }
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 38)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                // 直接使用 Finder/Dock 为应用包返回的图标；侧边栏品牌图标按 64pt 展示。
                Text(QuotaMonitorIdentity.displayName)
                    .font(Font.custom("PingFang SC", size: 15.5).weight(.semibold))
                    .foregroundStyle(sidebarBrandForeground)
            }
            .padding(.horizontal, MainPanelLayout.sidebarLeadingInset)
            .padding(.top, 10)
            .padding(.bottom, 14)

            VStack(spacing: 3) {
                ForEach(DashboardPage.allCases, id: \.self) { page in
                    Button {
                        selectPage(page)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.iconName)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .frame(width: 15)
                            Text(language.text(page.titleKey))
                                .font(.system(size: 12, weight: selectedPage == page ? .semibold : .regular, design: .monospaced))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(sidebarItemForeground(for: page))
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
        .background {
            if reduceTransparency {
                PanelTheme.sidebar
            } else {
                PanelVisualEffect(material: .sidebar, blendingMode: .behindWindow)
            }
        }
        // 页面内容保留原来的淡入动画，侧栏材质和选中胶囊不参与动画事务，
        // 避免切换 Tab 时重新合成模糊层。
        .transaction { transaction in
            transaction.animation = nil
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(PanelTheme.hairline)
                .frame(width: 1)
        }
    }

    private var sidebarBrandForeground: Color {
        colorScheme == .dark ? .white : PanelTheme.text
    }

    private func sidebarItemForeground(for page: DashboardPage) -> Color {
        if colorScheme == .dark {
            return .white
        }
        return selectedPage == page ? PanelTheme.text : PanelTheme.text2
    }

    @ViewBuilder
    var pageContent: some View {
        switch selectedPage {
        case .overview:
            overviewPage
        case .tokens:
            tokenPage
        case .settings:
            settingsPage
        }
    }

    var emptyState: some View {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var loadingProgressText: String {
        guard let progress = store.localTokenRefreshProgress else {
            return language.text("panel.syncingDetail")
        }
        return language.text(
            "panel.statusProgress",
            progress.completedSources,
            progress.totalSources
        )
    }

    func loadingPlaceholder(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(PanelTheme.surface.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .opacity(reduceMotion ? 0.72 : 0.88)
    }

    func errorBanner(message: String) -> some View {
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

    var sharedBalanceText: String {
        guard let balance = store.deepSeekBalance else { return "--" }
        return QuotaFormatters.money(balance, currency: store.deepSeekCurrency)
    }

    var codexProvider: ProviderUsage? {
        store.providers.first { $0.providerId.lowercased() == "codex" }
    }

    func legendItem(_ color: Color, _ title: String) -> some View {
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

    struct ModelRow: Identifiable {
        let model: String
        let total: Int
        let share: Double

        var id: String { model }
    }

    func panelCard(
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
