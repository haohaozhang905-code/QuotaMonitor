import AppKit
import SwiftUI

@main
struct QuotaMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 设置已融入主面板，保留空 Settings 场景仅为满足 App 协议要求。
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = QuotaStore()
    let language = LanguageSettings()

    private var statusItem: NSStatusItem?
    private var panelController: MainPanelController?
    private var refreshTask: Task<Void, Never>?
    private var menuBarUpdateTask: Task<Void, Never>?
    private var renderedMenuBarState: MenuBarRenderState?

    private struct MenuBarRenderState: Equatable {
        let codexRoute: CodexRoute
        let claudeRoute: ClaudeRoute
        let codexRemaining: Double?
        let balanceAmount: Double?
        let balanceCurrency: String?
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else { return }
        NSApp.setActivationPolicy(.accessory)
        // 改造版视觉标准以暗黑界面为默认外观；保留环境变量作为验收脚本的显式开关。
        if ProcessInfo.processInfo.environment["CODEXQUOTA_FORCE_DARK"] == "1"
            || UserDefaults.standard.object(forKey: "QuotaMonitor.useDarkAppearance") == nil
            || UserDefaults.standard.bool(forKey: "QuotaMonitor.useDarkAppearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        setupStatusItem()
        panelController = MainPanelController(store: store, language: language)
        observeStore()
        refreshTask = Task { await store.start() }
        // 调试/验收用：设置 CODEXQUOTA_SHOW_PANEL=1 时启动即展示主面板。
        if ProcessInfo.processInfo.environment["CODEXQUOTA_SHOW_PANEL"] == "1" {
            showMainPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        menuBarUpdateTask?.cancel()
    }

    /// 点击 Dock 图标时重新打开主面板。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainPanel()
        return true
    }

    // MARK: - 菜单栏状态项

    private func enforceSingleInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentPID }
        guard let existing else { return true }

        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.isBordered = false
            if let cell = button.cell as? NSButtonCell {
                cell.highlightsBy = []
                cell.showsStateBy = []
            }
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel(QuotaMonitorIdentity.displayName)
        }
        statusItem = item
        updateMenuBarContent()
    }

    private var menuBarRenderState: MenuBarRenderState {
        let codex = store.providers.first { $0.providerId.lowercased() == "codex" }
        return MenuBarRenderState(
            codexRoute: store.codexRoute,
            claudeRoute: store.claudeUsesDeepSeek ? .deepseek : store.claudeRouteSummary,
            codexRemaining: codex?.weekly?.remainingPercent,
            balanceAmount: store.deepSeekBalance,
            balanceCurrency: store.deepSeekCurrency
        )
    }

    private func menuBarContent(for state: MenuBarRenderState) -> MenuBarSlotsView {
        MenuBarSlotsView(
            codexRoute: state.codexRoute,
            claudeRoute: state.claudeRoute,
            codexRemaining: state.codexRemaining,
            claudeRemaining: nil,
            balanceAmount: state.balanceAmount,
            balanceCurrency: state.balanceCurrency
        )
    }

    /// 刷新菜单栏内容并按内容重新调整状态项宽度。
    private func updateMenuBarContent() {
        let state = menuBarRenderState
        guard state != renderedMenuBarState else { return }
        menuBarUpdateTask?.cancel()
        menuBarUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard let self, self.menuBarRenderState == state else { return }
            self.renderMenuBarContent(for: state)
        }
    }

    private func renderMenuBarContent(for state: MenuBarRenderState) {
        guard let button = statusItem?.button else { return }
        let renderer = ImageRenderer(
            content: menuBarContent(for: state)
                .padding(.horizontal, 1)
                .padding(.vertical, 3)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        image.isTemplate = false
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        statusItem?.length = ceil(image.size.width) + 8
        renderedMenuBarState = state
    }

    /// 用 Observation 追踪 store 变化，菜单栏文字自动跟随。
    private func observeStore() {
        withObservationTracking {
            _ = store.codexRoute
            _ = store.claudeRoute
            _ = store.claudeDesktopRoute
            _ = store.deepSeekBalance
            _ = store.providers.count
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMenuBarContent()
                self?.observeStore()
            }
        }
    }

    /// 所有状态栏点击都打开下拉框，主面板只从下拉框动作进入。
    @objc private func statusItemClicked() {
        showDropDownMenu()
    }

    // MARK: - 下拉框

    private func showDropDownMenu() {
        guard let button = statusItem?.button,
              let window = button.window else { return }
        let menu = makeMenu()
        menu.update()

        let buttonRectOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? buttonRectOnScreen
        let edgeInset: CGFloat = 8
        let desiredLeft = buttonRectOnScreen.midX - menu.size.width / 2
        let minimumLeft = visibleFrame.minX + edgeInset
        let maximumLeft = visibleFrame.maxX - menu.size.width - edgeInset
        let clampedLeft = min(max(desiredLeft, minimumLeft), max(minimumLeft, maximumLeft))
        let anchorOnScreen = NSPoint(x: clampedLeft, y: buttonRectOnScreen.minY - 3)
        let anchorInWindow = window.convertFromScreen(NSRect(origin: anchorOnScreen, size: .zero)).origin
        let anchorInButton = button.convert(anchorInWindow, from: nil)
        button.highlight(true)
        menu.popUp(positioning: nil, at: anchorInButton, in: button)
        button.highlight(false)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let presentation = store.dropdownPresentation
        let information = VStack(spacing: 0) {
            DropdownHeader(title: QuotaMonitorIdentity.displayName, updated: updatedText(for: presentation))
            DropdownHero(
                value: heroValue(for: presentation),
                label: language.text("menu.todayTokensLabel"),
                comparison: heroComparison(for: presentation),
                comparisonColor: comparisonColor(for: presentation.today.trendPercent)
            )
            if let status = dropdownStatus(for: presentation.availability) {
                DropdownStatusRow(text: status.text, tone: status.tone)
            }
            if !presentation.quotaItems.isEmpty {
                DropdownSectionHeader(title: language.text("menu.quotaSection"))
                ForEach(presentation.quotaItems) { item in
                    self.quotaLine(
                        icon: self.icon(for: item.platform),
                        title: item.platform.displayName,
                        state: item.state
                    )
                }
            }
            DropdownSectionHeader(title: language.text("menu.platformSection"))
            if presentation.platformToday.isEmpty {
                DropdownEmptyRow(text: language.text("menu.noUsage"))
            } else {
                ForEach(presentation.platformToday) { row in
                    DropdownCompactRow(
                        name: row.key.displayName(claudeCode: self.language.text("panel.claudeCode")),
                        amount: QuotaFormatters.tokensCN(row.total),
                        share: self.percentText(row.share)
                    )
                }
            }
            DropdownSectionHeader(title: language.text("menu.modelSection"))
            if presentation.topModels.isEmpty {
                DropdownEmptyRow(text: language.text("menu.noUsage"))
            } else {
                ForEach(presentation.topModels) { row in
                    DropdownCompactRow(
                        name: row.key.displayName(other: self.language.text("tokens.otherModel")),
                        amount: QuotaFormatters.tokensCN(row.total),
                        share: self.percentText(row.share)
                    )
                }
            }
            Color.clear.frame(height: 10)
        }
        .fontDesign(.monospaced)
        menu.addItem(DropdownRows.menuItem(information))

        let open = monoMenuItem(
            title: language.text("menu.openPanel"),
            action: #selector(showMainPanel),
            keyEquivalent: "o"
        )
        open.target = self
        menu.addItem(open)

        let refresh = monoMenuItem(
            title: language.text("menu.refresh"),
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        let settings = monoMenuItem(
            title: language.text("menu.settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = monoMenuItem(
            title: language.text("menu.quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.image = nil
        menu.addItem(quit)
        return menu
    }

    private func monoMenuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        let font = NSFont(name: "SFMono-Regular", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        return item
    }

    private func updatedText(for presentation: DropdownPresentation) -> String {
        guard let date = presentation.updatedAt else { return language.text("menu.notUpdated") }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return language.text("menu.updatedAt", formatter.string(from: date))
    }

    private func heroValue(for presentation: DropdownPresentation) -> String {
        switch presentation.availability {
        case .ready, .stale:
            QuotaFormatters.tokensCN(presentation.today.total)
        case .loading, .connectedOnly, .unavailable, .error:
            "—"
        }
    }

    private func heroComparison(for presentation: DropdownPresentation) -> String? {
        switch presentation.availability {
        case .ready, .stale:
            comparisonText(for: presentation.today.trendPercent)
        case .loading, .connectedOnly, .unavailable, .error:
            nil
        }
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func comparisonText(for percent: Double?) -> String? {
        guard let percent else { return nil }
        let key = percent >= 0 ? "menu.vsYesterdayUp" : "menu.vsYesterdayDown"
        return language.text(key, String(format: "%.1f", abs(percent)))
    }

    private func comparisonColor(for percent: Double?) -> Color {
        guard let percent else { return .secondary }
        return percent >= 0 ? PanelTheme.claude : PanelTheme.ok
    }

    private struct DropdownStatus {
        let text: String
        let tone: DropdownStatusTone
    }

    private func dropdownStatus(for availability: QuotaAvailability) -> DropdownStatus? {
        switch availability {
        case .ready:
            nil
        case .loading:
            .init(text: language.text("menu.statusLoading"), tone: .neutral)
        case .connectedOnly:
            .init(text: language.text("menu.statusConnectedNoQuota"), tone: .warning)
        case .unavailable:
            .init(text: language.text("menu.statusUnavailable"), tone: .warning)
        case .stale:
            .init(text: language.text("menu.statusStale"), tone: .warning)
        case .error:
            .init(text: language.text("menu.statusError"), tone: .danger)
        }
    }

    // MARK: - 下拉框数据

    private func icon(for platform: TokenPlatform) -> BrandIconKind {
        switch platform {
        case .codex: .codex
        case .claude: .claude
        case .workbuddy: .workBuddy
        case .kimi: .deepSeek
        }
    }

    @ViewBuilder
    private func quotaLine(icon: BrandIconKind, title: String, state: DropdownQuotaState) -> some View {
        switch state {
        case let .official(plan, session, weekly):
            DropdownQuotaLine(
                icon: icon,
                title: title,
                route: plan ?? language.text("panel.official"),
                metrics: [
                    quotaMetric(label: language.text("overview.sessionQuota"), metric: session),
                    quotaMetric(label: language.text("overview.weekQuota"), metric: weekly)
                ]
            )
        case let .sharedBalance(amount, currency, estimatedDays):
            DropdownQuotaLine(
                icon: icon,
                title: title,
                route: language.text("panel.deepSeekRouteTag"),
                metrics: [
                    .init(label: language.text("overview.sharedBalance"), value: QuotaFormatters.money(amount, currency: currency), detail: ""),
                    .init(label: language.text("overview.estimatedDays"), value: estimatedDays.map { language.text("panel.daysShortLabel", "\($0)") } ?? "—", detail: "")
                ]
            )
        case .connectedWithoutQuota:
            DropdownQuotaStatusLine(
                icon: icon,
                title: title,
                status: language.text("menu.quotaConnectedNoData"),
                tone: .warning
            )
        case .unavailable:
            DropdownQuotaStatusLine(
                icon: icon,
                title: title,
                status: language.text("menu.quotaUnavailable"),
                tone: .neutral
            )
        }
    }

    private func quotaMetric(
        label: String,
        metric: DropdownQuotaMetricPresentation?
    ) -> DropdownQuotaLine.Metric {
        let detail = metric?.resetsAt.map {
            language.text("overview.resetAfter", QuotaFormatters.reset(language: language.language).string(from: $0))
        } ?? ""
        return .init(
            label: label,
            value: metric?.remainingPercent.map(QuotaFormatters.percent) ?? "—",
            detail: detail
        )
    }

    // MARK: - 主面板

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }

    @objc func showMainPanel() {
        panelController?.show()
    }

    @objc private func showSettings() {
        NotificationCenter.default.post(name: .quotaMonitorOpenSettings, object: nil)
        panelController?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}
