import SwiftUI

/// Capability support and temporary scan states are not failures.
enum SourceCapabilityPresentation: Equatable {
    case ready, notProvided, noData, notDetected, scanning
    case needsPermission, unsupportedFormat, stale, failed

    init(states: [DataSourceHealthState]) {
        if states.contains(.ready) { self = .ready; return }
        let priority: [DataSourceHealthState] = [.needsPermission, .failed, .unsupportedFormat, .stale, .scanning, .noData, .notDetected]
        guard let state = priority.first(where: { states.contains($0) }) else { self = .notProvided; return }
        self = switch state {
        case .ready: .ready
        case .scanning: .scanning
        case .noData: .noData
        case .notDetected: .notDetected
        case .needsPermission: .needsPermission
        case .unsupportedFormat: .unsupportedFormat
        case .stale: .stale
        case .failed: .failed
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .needsPermission, .unsupportedFormat, .stale: "exclamationmark.circle"
        case .scanning: "arrow.triangle.2.circlepath"
        case .notProvided, .noData, .notDetected: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .ready: PanelTheme.success
        case .failed: PanelTheme.danger
        case .needsPermission, .unsupportedFormat, .stale: PanelTheme.warn
        case .notProvided, .noData, .notDetected, .scanning: PanelTheme.text2
        }
    }

    var reasonKey: String? {
        switch self {
        case .ready: nil
        case .notProvided: "settings.sources.table.reason.noSource"
        case .noData: "settings.sources.table.reason.noData"
        case .notDetected: "settings.sources.table.reason.notDetected"
        case .scanning: "settings.sources.table.reason.scanning"
        case .needsPermission: "settings.sources.table.reason.permission"
        case .unsupportedFormat: "settings.sources.table.reason.unsupported"
        case .stale: "settings.sources.table.reason.stale"
        case .failed: "settings.sources.table.reason.failed"
        }
    }
}
