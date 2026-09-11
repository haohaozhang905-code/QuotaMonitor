import Observation
import OSLog
import ServiceManagement

@MainActor @Observable
final class LoginItemManager {
    static let initializedKey = "QuotaMonitor.launchAtLoginInitialized"

    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?

    private let service = SMAppService.mainApp
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.cmsjcm.QuotaMonitor", category: "login-item")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerByDefaultIfNeeded()
        refresh()
    }

    /// 新安装默认注册登录启动；只尝试一次，之后尊重用户在应用或系统设置中的选择。
    private func registerByDefaultIfNeeded() {
        guard defaults.object(forKey: Self.initializedKey) == nil else { return }
        defaults.set(true, forKey: Self.initializedKey)
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
            logger.info("Login item registered by first-run default")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Default login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func statusText(language: LanguageSettings) -> String {
        switch status {
        case .enabled: language.text("login.enabled")
        case .notRegistered: language.text("login.disabled")
        case .requiresApproval: language.text("login.requiresApproval")
        case .notFound: language.text("login.disabled")
        @unknown default: language.text("login.unknown")
        }
    }

    func refresh() {
        status = service.status
        logger.info("Login item status: \(self.status.rawValue, privacy: .public)")
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.initializedKey)
        errorMessage = nil
        do {
            if enabled {
                guard status != .enabled && status != .requiresApproval else {
                    refresh()
                    return
                }
                try service.register()
                logger.info("Login item registered")
            } else {
                guard status != .notRegistered else {
                    refresh()
                    return
                }
                try service.unregister()
                logger.info("Login item unregistered")
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
