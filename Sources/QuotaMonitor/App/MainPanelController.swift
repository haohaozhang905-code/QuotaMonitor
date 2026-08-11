import AppKit
import SwiftUI

/// 主面板窗口：承载 MainPanelView，单例常驻，由菜单栏与小组件唤起。
@MainActor
final class MainPanelController: NSObject {
    let panel: NSPanel
    private let defaultContentSize = NSSize(width: 980, height: 620)

    init(store: QuotaStore, language: LanguageSettings) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        super.init()

        // 内容延伸到标题栏下方，让原生交通灯与设计稿中的侧栏顶部保持一致。
        panel.title = QuotaMonitorIdentity.displayName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(PanelTheme.background)
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        // 只允许从原生标题栏（顶部交通灯所在横条）拖动，内容区空白不再劫持点击。
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.minSize = NSSize(width: 820, height: 540)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("")

        let hosting = NSHostingView(rootView: MainPanelView(store: store, language: language))
        hosting.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

    }

    func show() {
        if !panel.isVisible {
            panel.setContentSize(defaultContentSize)
            panel.center()
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeKey()
        }
    }

    func close() {
        panel.orderOut(nil)
    }

    func toggle() {
        panel.isVisible ? close() : show()
    }
}
