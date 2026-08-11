import Observation
import OSLog
import ServiceManagement

@MainActor @Observable
final class LoginItemManager {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?

    private let service = SMAppService.mainApp
    private let logger = Logger(subsystem: "com.cmsjcm.QuotaMonitor", category: "login-item")

    init() {
        refresh()
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
