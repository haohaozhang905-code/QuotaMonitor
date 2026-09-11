import AppKit
import SwiftUI
import UserNotifications

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

@MainActor
final class ReminderDeliveryController {
    private static let toastOuterPadding: CGFloat = 14
    private struct ToastEntry {
        let id: String
        let panel: NSPanel
        let size: NSSize
        var dismissTask: Task<Void, Never>?
    }

    private let settings: ReminderSettings
    private var toastEntries: [ToastEntry] = []

    var statusItemButton: NSStatusBarButton?
    var openReminder: ((ReminderPresentation) -> Void)?

    init(settings: ReminderSettings) {
        self.settings = settings
    }

    func refreshAuthorizationState() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        settings.updateSystemAuthorization(Self.authorizationState(notificationSettings.authorizationStatus))
    }

    func handleSystemNotificationPreference(_ enabled: Bool) {
        guard enabled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            } catch {
                self.settings.updateSystemAuthorization(.denied)
                return
            }
            await self.refreshAuthorizationState()
        }
    }

    func deliver(presentations: [ReminderPresentation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var applicationPresentations: [ReminderPresentation] = []
            for presentation in presentations {
                if await self.deliverSystemNotificationIfAvailable(presentation) { continue }
                applicationPresentations.append(presentation)
            }
            if !applicationPresentations.isEmpty {
                self.showToastPanels(applicationPresentations)
            }
        }
    }

    func closeToastPanel() {
        let entries = toastEntries
        toastEntries.removeAll()
        for entry in entries {
            entry.dismissTask?.cancel()
            entry.panel.orderOut(nil)
        }
    }

    private func deliverSystemNotificationIfAvailable(
        _ presentation: ReminderPresentation,
        requiresPreference: Bool = true
    ) async -> Bool {
        if requiresPreference, !settings.prefersSystemNotifications { return false }
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        settings.updateSystemAuthorization(Self.authorizationState(notificationSettings.authorizationStatus))
        guard [.authorized, .provisional].contains(notificationSettings.authorizationStatus) else { return false }

        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.body = presentation.body
        content.userInfo = ["destination": presentation.destination.rawValue]
        let request = UNNotificationRequest(identifier: presentation.id, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func showToastPanels(
        _ presentations: [ReminderPresentation],
        autoDismissAfter: Duration = .seconds(8)
    ) {
        closeToastPanel()
        for presentation in presentations {
            createToastPanel(presentation)
        }
        repositionToastPanels()
        for entry in toastEntries {
            entry.panel.orderFrontRegardless()
            scheduleToastDismiss(id: entry.id, after: autoDismissAfter)
        }
    }

    private func createToastPanel(_ presentation: ReminderPresentation) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 原生窗口阴影：跟随卡片不透明内容形状，避免在透明 padding 区合成灰色环
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true

        let root = ReminderToastView(
            presentation: presentation,
            onOpen: { [weak self] in
                self?.closeToastPanel(id: presentation.id)
                self?.openReminder?(presentation)
            },
            onClose: { [weak self] in self?.closeToastPanel(id: presentation.id) },
            onHoverChange: { [weak self] hovering in self?.setToastHovering(id: presentation.id, hovering) }
        )
        .padding(Self.toastOuterPadding)
        let hosting = TransparentHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        let fitting = hosting.fittingSize
        let size = NSSize(
            width: ReminderToastView.cardWidth + Self.toastOuterPadding * 2,
            height: min(max(fitting.height, 104), 280)
        )
        panel.setContentSize(size)
        toastEntries.append(ToastEntry(id: presentation.id, panel: panel, size: size))
    }

    private func repositionToastPanels() {
        var verticalOffset: CGFloat = 0
        for entry in toastEntries {
            entry.panel.setFrameOrigin(toastOrigin(size: entry.size, verticalOffset: verticalOffset))
            verticalOffset += max(72, entry.size.height - Self.toastOuterPadding * 2 + 8)
        }
    }

    private func toastOrigin(size: NSSize, verticalOffset: CGFloat = 0) -> NSPoint {
        if let button = statusItemButton, let window = button.window {
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? buttonRect
            let fallback = NSPoint(
                x: visible.maxX - size.width - 14,
                y: visible.maxY - size.height - 14 - verticalOffset
            )
            guard buttonRect.midY >= visible.midY else { return fallback }
            return NSPoint(
                x: min(max(buttonRect.midX - size.width / 2, visible.minX), visible.maxX - size.width),
                y: min(
                    max(buttonRect.minY - size.height + 10 - verticalOffset, visible.minY),
                    visible.maxY - size.height
                )
            )
        }
        let visible = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(
            x: visible.maxX - size.width - 14,
            y: visible.maxY - size.height - 14 - verticalOffset
        )
    }

    private func closeToastPanel(id: String) {
        guard let index = toastEntries.firstIndex(where: { $0.id == id }) else { return }
        let entry = toastEntries.remove(at: index)
        entry.dismissTask?.cancel()
        entry.panel.orderOut(nil)
        repositionToastPanels()
    }

    private func setToastHovering(id: String, _ hovering: Bool) {
        guard let index = toastEntries.firstIndex(where: { $0.id == id }) else { return }
        if hovering {
            toastEntries[index].dismissTask?.cancel()
            toastEntries[index].dismissTask = nil
        } else {
            scheduleToastDismiss(id: id)
        }
    }

    private func scheduleToastDismiss(id: String, after duration: Duration = .seconds(8)) {
        guard let index = toastEntries.firstIndex(where: { $0.id == id }) else { return }
        toastEntries[index].dismissTask?.cancel()
        toastEntries[index].dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.closeToastPanel(id: id)
        }
    }

    private static func authorizationState(_ status: UNAuthorizationStatus) -> SystemNotificationAuthorizationState {
        switch status {
        case .notDetermined: .notRequested
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .unknown
        }
    }
}
