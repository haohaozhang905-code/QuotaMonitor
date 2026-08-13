import AppKit
import SwiftUI
import QuartzCore
import Observation

enum DockIconMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case always
    case never

    var id: String { rawValue }
}

@MainActor @Observable
final class DockIconSettings {
    static let storageKey = "QuotaMonitor.dockIconMode"

    var mode: DockIconMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            onChange?(mode)
        }
    }

    @ObservationIgnored var onChange: ((DockIconMode) -> Void)?

    init() {
        mode = UserDefaults.standard.string(forKey: Self.storageKey)
            .flatMap(DockIconMode.init(rawValue:)) ?? .smart
    }
}

/// 主面板窗口：平时维持菜单栏轻量形态，打开后切换为可从 Dock 找回的标准窗口。
@MainActor
final class MainPanelController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let dockIconSettings: DockIconSettings

    init(store: QuotaStore, language: LanguageSettings, dockIconSettings: DockIconSettings) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.window = window
        self.dockIconSettings = dockIconSettings
        super.init()

        // 内容延伸到标题栏下方：侧栏覆盖交通灯区域，主内容保留自己的顶部状态栏。
        window.title = QuotaMonitorIdentity.displayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor(PanelTheme.background)
        window.hasShadow = false
        window.level = .normal
        window.delegate = self
        // 只允许从原生标题栏（顶部交通灯所在横条）拖动，内容区空白不再劫持点击。
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.minSize = NSSize(width: 820, height: 540)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        let frameName = "QuotaMonitor.MainPanel"
        if !window.setFrameUsingName(frameName) {
            window.center()
        }
        window.setFrameAutosaveName(frameName)

        let hosting = NSHostingView(rootView: MainPanelView(
            store: store,
            language: language,
            dockIconSettings: dockIconSettings
        ))
        hosting.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        NotificationCenter.default.addObserver(
            forName: .quotaMonitorToggleZoom,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.toggleZoom() }
        }
        dockIconSettings.onChange = { [weak self] _ in
            self?.applyDockPolicy()
        }
        applyDockPolicy()
        DispatchQueue.main.async { [weak self] in
            self?.alignTrafficLights()
        }
    }

    private func alignTrafficLights() {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        guard let container = buttons.first?.superview else { return }
        container.layoutSubtreeIfNeeded()
        guard let currentLeading = buttons.map(\.frame.minX).min() else { return }
        let delta = MainPanelLayout.sidebarLeadingInset - currentLeading
        guard abs(delta) > 0.5 else { return }
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: button.frame.minX + delta, y: button.frame.minY))
        }
    }

    func show() {
        applyDockPolicy(windowIsOpening: true)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            // 先让系统激活应用，再交给 NSWindow 还原；这样 Dock 的窗口缩略图
            // 会沿 macOS 的标准路径展开回主面板，而不是瞬移到桌面。
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard !window.isVisible else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let finalFrame = window.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = reduceMotion ? 1 : 0
        if !reduceMotion {
            window.setFrameOrigin(NSPoint(x: finalFrame.minX, y: finalFrame.minY - 8))
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        guard !reduceMotion else {
            window.makeKey()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak window] in
            Task { @MainActor in window?.makeKey() }
        }
    }

    func close() {
        guard window.isVisible || window.isMiniaturized else {
            applyDockPolicy()
            return
        }
        window.performClose(nil)
    }

    func toggle() {
        window.isVisible && !window.isMiniaturized ? close() : show()
    }

    private func toggleZoom() {
        guard window.isVisible else { return }
        window.zoom(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 等窗口完成关闭后再隐藏 Dock，避免切换过程中窗口与应用图标同时闪烁。
        DispatchQueue.main.async { [weak self] in
            self?.applyDockPolicy()
        }
    }

    private func applyDockPolicy(windowIsOpening: Bool = false) {
        let shouldShowDock = switch dockIconSettings.mode {
        case .smart: windowIsOpening || window.isVisible || window.isMiniaturized
        case .always: true
        case .never: false
        }
        NSApp.setActivationPolicy(shouldShowDock ? .regular : .accessory)
    }
}
