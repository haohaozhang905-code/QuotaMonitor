import AppKit
import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            srgbRed: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 主面板与下拉框共用的语义化色板。颜色按系统外观动态切换。
enum PanelTheme {
    static func dynamic(_ light: String, _ dark: String) -> Color {
        let dynamicColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
        return Color(nsColor: dynamicColor)
    }

    static let background = dynamic("#F6F6F7", "#15191F")
    static let sidebar = dynamic("#ECECEF", "#1C222B")
    static let surface = dynamic("#FFFFFF", "#20262F")
    static let surface2 = dynamic("#F3F3F5", "#272E38")
    static let surface3 = dynamic("#E8E8EC", "#323B47")
    // 边界只负责轻微分层；卡片和窗口主体主要依靠表面色差建立层级。
    static let border = dynamic("#E4E4E7", "#2C333C")
    static let borderStrong = dynamic("#D5D5DA", "#3A444F")
    static let separator = dynamic("#E9E9EC", "#29313A")
    static let text = dynamic("#19191C", "#E8EBF0")
    static let text2 = dynamic("#696971", "#97A0AC")
    static let text3 = dynamic("#9A9AA2", "#7B8593")
    static let codex = dynamic("#5B6F8D", "#6C82A3")
    static let codexDeep = dynamic("#4C607D", "#8296B5")
    static let codexSoft = dynamic("#E7EBF1", "#28323E")
    // Claude 官方品牌橙；图标在深浅色外观中均保持品牌原色。
    static let claude = Color(hex: "#D97757")
    static let claudeDeep = dynamic("#B85C3B", "#E68A6D")
    static let claudeSoft = dynamic("#F3E8E3", "#382D2A")
    static let claudeCode = dynamic("#77678B", "#8C7BA3")
    static let claudeCodeSoft = dynamic("#ECE8EF", "#302B38")
    static let deepseek = dynamic("#5D858D", "#6F98A0")
    static let deepseekSoft = dynamic("#E8EDFF", "#252D40")
    static let workbuddy = dynamic("#5E8975", "#78A18F")
    static let workbuddySoft = dynamic("#E4EFEA", "#293A34")
    static let modelFallback = dynamic("#8B877F", "#A5A19A")
    static let ok = dynamic("#2FA36B", "#69BD93")
    static let okSoft = dynamic("#E4F5EC", "#1F382D")
    static let warn = dynamic("#D99A2B", "#DCA869")
    static let warnSoft = dynamic("#FBF1DC", "#3A2D1D")
    static let danger = dynamic("#D9534F", "#E07C6C")
    static let dangerSoft = dynamic("#FBE7E6", "#3A2522")
    static let grid = dynamic("#E4E6EB", "#303844")
    static let shadowSmall = Color.black.opacity(0.05)
    static let shadow = Color.black.opacity(0.08)

    /// 平台与模型共用的五色分类色板。状态色（ok/warn/danger）不纳入分类色板。
    static let categoryPalette: [Color] = [codex, claude, claudeCode, workbuddy, modelFallback]
    /// 模型较多时沿用五个基础色的低饱和明度变体，不引入新的色相。
    static let categoryPaletteExtended: [Color] = categoryPalette + [
        dynamic("#7E91AE", "#8FA4C1"),
        dynamic("#C49A87", "#D0A999"),
        dynamic("#9D8FB0", "#AB9CBC"),
        dynamic("#8BAE9D", "#98B9A8"),
        dynamic("#B9B5AB", "#C9C5BB")
    ]

    static func modelColor(for model: String) -> Color {
        let hash = model.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return categoryPalette[Int(hash % UInt32(categoryPalette.count))]
    }
}
