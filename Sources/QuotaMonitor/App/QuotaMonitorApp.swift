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
    let dockIconSettings = DockIconSettings()

    private var statusItem: NSStatusItem?
    private var panelController: MainPanelController?
    private var refreshTask: Task<Void, Never>?
    private var menuBarUpdateTask: Task<Void, Never>?
    private var menuBarAnimationTask: Task<Void, Never>?
    private var dropdownPanel: NSPanel?
    private var dropdownEventMonitors: [Any] = []
    private var renderedMenuBarState: MenuBarRenderState?

    private struct MenuBarRenderState: Equatable {
        let codexRoute: CodexRoute
        let claudeRoute: ClaudeRoute
        let codexRemaining: Double?
        let balanceAmount: Double?
        let balanceCurrency: String?
        let isLoading: Bool
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else { return }
        configureApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        // 改造版视觉标准以暗黑界面为默认外观；保留环境变量作为验收脚本的显式开关。
        if ProcessInfo.processInfo.environment["CODEXQUOTA_FORCE_DARK"] == "1"
            || UserDefaults.standard.object(forKey: "QuotaMonitor.useDarkAppearance") == nil
            || UserDefaults.standard.bool(forKey: "QuotaMonitor.useDarkAppearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        setupStatusItem()
        panelController = MainPanelController(
            store: store,
            language: language,
            dockIconSettings: dockIconSettings
        )
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
        menuBarAnimationTask?.cancel()
        closeDropdownPanel(animated: false)
    }

    /// 点击 Dock 图标时重新打开主面板。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainPanel()
        return true
    }

    // MARK: - 菜单栏状态项

    private func configureApplicationIcon() {
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? QuotaResourceBundle.current.url(forResource: "AppIcon", withExtension: "png")
        if let iconURL, let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

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
            // 交给 NSStatusBarButton 绘制 macOS 原生 hover/pressed 容器，
            // 不再用自定义 CALayer 模拟状态栏点击态。
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.showsBorderOnlyWhileMouseInside = true
            if let cell = button.cell as? NSButtonCell {
                cell.highlightsBy = NSCell.StyleMask(rawValue: 1 | 8)
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
            balanceCurrency: store.deepSeekCurrency,
            isLoading: !store.hasCompletedInitialRefresh
        )
    }

    private func menuBarContent(for state: MenuBarRenderState, loadingFrame: Int = 0) -> MenuBarSlotsView {
        MenuBarSlotsView(
            codexRoute: state.codexRoute,
            claudeRoute: state.claudeRoute,
            codexRemaining: state.codexRemaining,
            claudeRemaining: nil,
            balanceAmount: state.balanceAmount,
            balanceCurrency: state.balanceCurrency,
            isLoading: state.isLoading,
            loadingFrame: loadingFrame
        )
    }

    /// 刷新菜单栏内容并按内容重新调整状态项宽度。
    private func updateMenuBarContent() {
        let state = menuBarRenderState
        if state.isLoading {
            startMenuBarLoadingAnimationIfNeeded()
            renderMenuBarContent(for: state, loadingFrame: 0)
            return
        }

        menuBarAnimationTask?.cancel()
        menuBarAnimationTask = nil
        guard state != renderedMenuBarState else { return }
        menuBarUpdateTask?.cancel()
        menuBarUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard let self, self.menuBarRenderState == state else { return }
            self.renderMenuBarContent(for: state)
        }
    }

    private func startMenuBarLoadingAnimationIfNeeded() {
        guard menuBarAnimationTask == nil else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            renderMenuBarContent(for: menuBarRenderState, loadingFrame: 2)
            return
        }

        menuBarAnimationTask = Task { @MainActor [weak self] in
            var frame = 0
            while !Task.isCancelled {
                guard let self, self.menuBarRenderState.isLoading else { break }
                self.renderMenuBarContent(for: self.menuBarRenderState, loadingFrame: frame)
                frame = (frame + 1) % 3
                try? await Task.sleep(for: .milliseconds(360))
            }
            self?.menuBarAnimationTask = nil
        }
    }

    private func renderMenuBarContent(for state: MenuBarRenderState, loadingFrame: Int = 0) {
        guard let button = statusItem?.button else { return }
        let renderer = ImageRenderer(
            content: menuBarContent(for: state, loadingFrame: loadingFrame)
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
            _ = store.hasCompletedInitialRefresh
            _ = store.localTokenRefreshProgress
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMenuBarContent()
                self?.observeStore()
            }
        }
    }

    /// 所有状态栏点击都打开下拉框，主面板只从下拉框动作进入。
    @objc private func statusItemClicked() {
        if dropdownPanel?.isVisible == true {
            closeDropdownPanel()
        } else {
            showDropdownPanel()
        }
    }

    // MARK: - 下拉框

    private func showDropdownPanel() {
        guard let button = statusItem?.button, let window = button.window else { return }

        closeDropdownPanel(animated: false)

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSApp.appearance ?? NSAppearance(named: .darkAqua)

        let rootView = DropdownPopoverView(
            store: store,
            language: language,
            openPanel: { [weak self] in
                self?.closeDropdownPanelThen {
                    self?.showMainPanel()
                }
            },
            refresh: { [weak self] in
                guard let self else { return }
                Task { await self.store.refreshAll() }
            },
            openSettings: { [weak self] in
                self?.closeDropdownPanelThen {
                    self?.showSettings()
                }
            },
            quit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController

        let fittingHeight = hostingController.view.fittingSize.height
        let panelSize = NSSize(
            width: DropdownLayout.width,
            height: min(max(fittingHeight, 300), 660)
        )
        panel.setContentSize(panelSize)

        let buttonRectOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? buttonRectOnScreen
        let edgeInset: CGFloat = 8
        let left = min(
            max(buttonRectOnScreen.midX - panelSize.width / 2, visibleFrame.minX + edgeInset),
            max(visibleFrame.minX + edgeInset, visibleFrame.maxX - panelSize.width - edgeInset)
        )
        let finalFrame = NSRect(
            x: left,
            y: buttonRectOnScreen.minY - panelSize.height - 2,
            width: panelSize.width,
            height: panelSize.height
        )

        // 顶边固定在状态栏下方 2px，窗口从一条细缝向下展开。
        let collapsedHeight: CGFloat = 2
        let collapsedFrame = NSRect(
            x: finalFrame.minX,
            y: finalFrame.maxY - collapsedHeight,
            width: finalFrame.width,
            height: collapsedHeight
        )
        panel.setFrame(collapsedFrame, display: false)
        panel.alphaValue = 1
        dropdownPanel = panel
        installDropdownEventMonitors()
        setStatusItemHighlighted(true)
        panel.orderFrontRegardless()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(finalFrame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
                panel.animator().setFrame(finalFrame, display: true)
            }
        }
    }

    private func installDropdownEventMonitors() {
        removeDropdownEventMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.closeDropdownPanel()
            }
        }) {
            dropdownEventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let self, let panel = self.dropdownPanel, panel.isVisible else { return event }
            let statusWindow = self.statusItem?.button?.window
            if event.window !== panel && event.window !== statusWindow {
                self.closeDropdownPanel()
            }
            return event
        }) {
            dropdownEventMonitors.append(local)
        }
    }

    private func removeDropdownEventMonitors() {
        dropdownEventMonitors.forEach { NSEvent.removeMonitor($0) }
        dropdownEventMonitors.removeAll()
    }

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem?.button else { return }
        // NSButton.highlight(_:) 使用系统自己的状态栏高亮绘制，
        // 包括当前 macOS 的 hover/pressed 容器形状和材质。
        button.highlight(highlighted)
    }

    private func closeDropdownPanel(animated: Bool = true) {
        guard let panel = dropdownPanel else {
            removeDropdownEventMonitors()
            setStatusItemHighlighted(false)
            return
        }
        removeDropdownEventMonitors()
        setStatusItemHighlighted(false)

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            if dropdownPanel === panel { dropdownPanel = nil }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                if self?.dropdownPanel === panel { self?.dropdownPanel = nil }
            }
        }
    }

    private func closeDropdownPanelThen(_ action: @escaping @MainActor () -> Void) {
        closeDropdownPanel()
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.14
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }

    // MARK: - 主面板

    @objc func showMainPanel() {
        panelController?.show()
    }

    @objc private func showSettings() {
        NotificationCenter.default.post(name: .quotaMonitorOpenSettings, object: nil)
        panelController?.show()
    }

}
