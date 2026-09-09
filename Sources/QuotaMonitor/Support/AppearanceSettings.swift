import AppKit
import Observation

/// 应用外观模式：跟随系统 / 浅色 / 深色。
/// 与主面板设置页「外观」联动，选择持久化到 UserDefaults；
/// 通过设置 NSApp.appearance 让 PanelTheme 的 dynamic 色自动切换。
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

@MainActor @Observable
final class AppearanceSettings {
    static let storageKey = "QuotaMonitor.appearance"
    /// 旧版开关（阶段 1 前存在），启动时自动迁移，不再写入。
    private static let legacyDarkKey = "QuotaMonitor.useDarkAppearance"

    var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            apply()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.storageKey),
           let mode = AppearanceMode(rawValue: raw) {
            self.mode = mode
        } else if defaults.object(forKey: Self.legacyDarkKey) != nil {
            // 迁移旧版开关：true=深色，false=跟随系统；迁移后旧 key 不再生效。
            self.mode = defaults.bool(forKey: Self.legacyDarkKey) ? .dark : .system
        } else {
            self.mode = .system
        }
    }

    /// 将当前模式应用到 NSApp。启动完成后调用一次，切换时由 didSet 自动调用。
    func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
