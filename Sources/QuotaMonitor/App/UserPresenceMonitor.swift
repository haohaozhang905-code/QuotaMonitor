import AppKit
import CoreGraphics

enum ReminderLockState { case unknown, locked, unlocked }

struct ReminderPresenceState {
    var lockState: ReminderLockState = .unknown
    var systemSleeping = false
    var screenSleeping = false

    func allowsNotification(hasAwakeDisplay: Bool) -> Bool {
        // The built-in display can sleep while an external screen remains in use.
        lockState == .unlocked && !systemSleeping && hasAwakeDisplay
    }
}

/// Whether a notification can be shown to the person using this Mac.
/// The distributed lock names are an OS compatibility adapter, so an unknown
/// lock state stays closed until an unlock signal or explicit app interaction.
@MainActor
final class UserPresenceMonitor {
    private var state = ReminderPresenceState()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var lastReportedEligibility = false
    private(set) var generation = 0
    var onEligibilityChanged: ((Bool) -> Void)?

    init() {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            state.lockState = locked ? .locked : .unlocked
        }
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.screensDidSleepNotification) { $0.state.screenSleeping = true }
        observe(center, NSWorkspace.screensDidWakeNotification) { $0.state.screenSleeping = false }
        observe(center, NSWorkspace.willSleepNotification) { $0.state.systemSleeping = true }
        observe(center, NSWorkspace.willPowerOffNotification) { $0.state.systemSleeping = true }
        observe(center, NSWorkspace.didWakeNotification) { $0.state.systemSleeping = false }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.state.lockState = .locked }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { $0.state.lockState = .unknown }

        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.update { $0.state.lockState = locked ? .locked : .unlocked }
                }
            }
            lockObservers.append(token)
        }
        lastReportedEligibility = canNotify
    }

    var canNotify: Bool {
        guard state.lockState == .unlocked, !state.systemSleeping else { return false }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        let hasAwakeDisplay = displays.prefix(Int(count)).contains {
            CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0
        }
        return state.allowsNotification(hasAwakeDisplay: hasAwakeDisplay)
    }

    func confirmUserInteraction() {
        guard state.lockState != .unlocked else { return }
        update { $0.state.lockState = .unlocked }
    }

    func stop() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.removeAll()
        lockObservers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         change: @escaping @MainActor (UserPresenceMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update(change)
            }
        }
        workspaceObservers.append(token)
    }

    private func update(_ change: (UserPresenceMonitor) -> Void) {
        change(self)
        generation &+= 1
        let isEligible = canNotify
        if lastReportedEligibility != isEligible {
            lastReportedEligibility = isEligible
            onEligibilityChanged?(isEligible)
        }
    }
}
