import Foundation
import Observation

enum SystemNotificationAuthorizationState: String, Sendable {
    case unknown
    case notRequested
    case authorized
    case denied
}

@MainActor @Observable
final class ReminderSettings {
    static let enabledKey = "QuotaMonitor.remindersEnabled"
    static let systemNotificationsKey = "QuotaMonitor.systemNotificationsEnabled"

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onEnabledChange?(isEnabled)
        }
    }

    var prefersSystemNotifications: Bool {
        didSet {
            defaults.set(prefersSystemNotifications, forKey: Self.systemNotificationsKey)
            onSystemNotificationPreferenceChange?(prefersSystemNotifications)
        }
    }

    private(set) var systemAuthorizationState: SystemNotificationAuthorizationState = .unknown

    @ObservationIgnored var onSystemNotificationPreferenceChange: ((Bool) -> Void)?
    @ObservationIgnored var onEnabledChange: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 新安装默认开启两类提醒。系统通知首次运行时仍由 macOS 弹出授权确认。
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.enabledKey)
        prefersSystemNotifications = defaults.object(forKey: Self.systemNotificationsKey) == nil
            ? true
            : defaults.bool(forKey: Self.systemNotificationsKey)
    }

    func updateSystemAuthorization(_ state: SystemNotificationAuthorizationState) {
        systemAuthorizationState = state
        // 偏好值不能领先于 macOS 的真实授权；避免迁移或测试残留让开关
        // 显示为开启，但通知中心仍处于“尚未请求/已拒绝”状态。
        if state == .denied, prefersSystemNotifications {
            prefersSystemNotifications = false
        }
    }
}
