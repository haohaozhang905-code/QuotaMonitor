import AppKit
import SwiftUI

@main
struct QuotaMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarDropdownContent(appDelegate: appDelegate)
        } label: {
            MenuBarStatusLabel(store: appDelegate.store)
                .accessibilityLabel(QuotaMonitorIdentity.displayName)
        }
        .menuBarExtraStyle(.window)

        // 设置已融入主面板，保留空 Settings 场景仅为满足 App 协议要求。
        Settings { EmptyView() }
    }
}

/// 让 SwiftUI 直接把状态内容交给系统状态栏按钮渲染。
/// 系统由此能够在普通、按下和展开状态之间自动调整容器与前景色。
private struct MenuBarStatusLabel: View {
    let store: QuotaStore

    var body: some View {
        Image(nsImage: renderedImage)
            .renderingMode(.original)
    }

    private var codexRemaining: Double? {
        store.providers.first { $0.providerId.lowercased() == "codex" }?
            .weekly?.remainingPercent
    }

    /// 沿用 8777a5b 的状态栏内容渲染方式，只将输出交给当前 MenuBarExtra。
    private var renderedImage: NSImage {
        let renderer = ImageRenderer(
            content: MenuBarSlotsView(
                codexRoute: store.codexRoute,
                claudeRoute: store.claudeDisplayRoute,
                codexRemaining: codexRemaining,
                claudeRemaining: nil,
                balanceAmount: store.deepSeekBalance,
                balanceCurrency: store.deepSeekCurrency,
                isLoading: !store.hasCompletedInitialRefresh
            )
            .padding(.horizontal, 1)
            .padding(.vertical, 3)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return MenuBarQuotaGlyph.image }
        image.isTemplate = false
        return image
    }
}

/// 系统窗口中的现有下拉内容。关闭动作交给 MenuBarExtra，避免维护额外的
/// NSPanel、全局事件监听和 NSStatusBarButton 高亮状态。
private struct MenuBarDropdownContent: View {
    let appDelegate: AppDelegate

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DropdownPopoverView(
            store: appDelegate.store,
            language: appDelegate.language,
            openPanel: openMainPanel,
            refresh: refresh,
            openSettings: openSettings,
            quit: { NSApp.terminate(nil) }
        )
    }

    private func openMainPanel() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            appDelegate.showMainPanel()
        }
    }

    private func refresh() {
        Task { await appDelegate.store.refreshAll() }
    }

    private func openSettings() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            appDelegate.showSettings()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = QuotaStore()
    let language = LanguageSettings()
    let dockIconSettings = DockIconSettings()

    private var panelController: MainPanelController?
    private var refreshTask: Task<Void, Never>?

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
        panelController = MainPanelController(
            store: store,
            language: language,
            dockIconSettings: dockIconSettings
        )
        refreshTask = Task { await store.start() }
        // 调试/验收用：设置 CODEXQUOTA_SHOW_PANEL=1 时启动即展示主面板。
        if ProcessInfo.processInfo.environment["CODEXQUOTA_SHOW_PANEL"] == "1" {
            showMainPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    /// 点击 Dock 图标时重新打开主面板。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainPanel()
        return true
    }

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

    @objc func showMainPanel() {
        panelController?.show()
    }

    @objc func showSettings() {
        NotificationCenter.default.post(name: .quotaMonitorOpenSettings, object: nil)
        panelController?.show()
    }
}
