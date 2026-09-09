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
///
/// 2026-09-09 · Steep 视觉升级 · 阶段 1（配色迁移）
/// - 依据：designs/codexquota-redesign/steep-design-system/DESIGN.md
/// - 旧 API 名称全部保留（调用方零改动），值按迁移表替换为新语义色
/// - 新增语义 token（bg/ink/paper/mist/fog/…/chart*/heat*）供后续阶段使用
/// - 已废弃语义（surface3 / borderStrong / 各 Soft 彩色底）暂保留过渡值，阶段 3 清理
/// - 品牌图标 / 平台主色 / 字体均不在本次改动范围
enum PanelTheme {
    static func dynamic(_ light: String, _ dark: String) -> Color {
        let dynamicColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
        return Color(nsColor: dynamicColor)
    }

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        let dynamicColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        return Color(nsColor: dynamicColor)
    }

    // MARK: - Steep 语义色板（新增，规范 DESIGN §2）

    /// 窗口 / 画布背景。浅色=白纸，深色=近黑
    static let bg = dynamic("#FFFFFF", "#111215")
    /// 主文字 / 填充按钮底 / 墨面。深色=夜羊皮纸，避免近白刺眼
    static let ink = dynamic("#17191C", "#CFCBC2")
    /// 浮动卡表面（下拉框 / 模态 / 浮动图表卡）
    static let paper = dynamic("#FFFFFF", "#17181C")
    /// 雾灰静面卡（额度卡 / 排行卡 / 设置分组）
    static let mist = dynamic("#F2F2F3", "#1B1C20")
    /// 分区背景（侧栏 / 交替区）
    static let fog = dynamic("#FAFAFB", "#131417")
    /// 次级文字 / 链接 / 正常状态字（幽灵灰）
    static let slate = dynamic("#777B86", "#A29F98")
    /// 三级标签 / 坐标轴文字
    static let ash = dynamic("#979799", "#7C7A75")
    /// 占位 / 禁用
    static let smoke = dynamic("#A3A6AF", "#585752")
    /// 桃面（提醒卡 / 桃底标签底色）。深色档压暗避免过亮
    static let peach = dynamic("#FBE1D1", "#D5AE93")
    /// 桃面上的文字与图表笔势。深底上的强调文字请用 chartAccent
    static let sienna = dynamic("#5D2A1A", "#5D2A1A")
    /// 卡片内分隔线 / 浮卡描边
    static let hairline = dynamic(NSColor(hex: "#ECECEC"), NSColor(white: 1, alpha: 0.08))
    /// 更强一级的分隔线：下拉框区块分隔等需要明确分界时使用
    static let hairlineStrong = dynamic(NSColor(hex: "#DEDEE2"), NSColor(white: 1, alpha: 0.14))
    /// 列表行分隔 / 极细描边
    static let hairlineSoft = dynamic(NSColor(srgbRed: 23/255, green: 25/255, blue: 28/255, alpha: 0.06), NSColor(white: 1, alpha: 0.055))
    /// 进度条轨道 / 内嵌槽
    static let track = dynamic(NSColor(srgbRed: 23/255, green: 25/255, blue: 28/255, alpha: 0.08), NSColor(white: 1, alpha: 0.07))

    // MARK: - 图表分类色（c1–c5）与热力图（h0–h4）

    /// c1 图表主系列
    static let chartPrimary = dynamic("#17191C", "#D8D4CA")
    /// c2 强调笔势（峰值 / 重点）
    static let chartAccent = dynamic("#5D2A1A", "#B38668")
    /// c3 分类色
    static let chartNeutral = dynamic("#777B86", "#8D8B92")
    /// c4 分类色（深色档已提亮保证深底可读）
    static let chartDim = dynamic("#A3A6AF", "#5C5E65")
    /// c5 分类色 · 暖沙
    static let chartSand = dynamic("#C9B9AE", "#7E6A58")

    /// 热力图最低档 h0（= mist）
    static let heat0 = mist
    /// 热力图第 2–4 档（ink 透明度近似，深色档与规范允许 ±0.1 偏差）
    static let heat1 = ink.opacity(0.22)
    static let heat2 = ink.opacity(0.45)
    static let heat3 = ink.opacity(0.72)
    /// 热力图最高档 h4（= ink）
    static let heat4 = ink

    // MARK: - 现有语义色板（阶段 1 迁移映射；DESIGN §9）

    // 画布与分区
    static let background = bg
    /// 侧栏导轨：比画布深一档，保证导航区与内容区层级明显
    static let sidebar = mist
    /// 静面卡底（迁移自 surface）
    static let surface = mist
    /// 浮卡底（新增；阶段 2 将图表卡 / 下拉框切换至此）
    static let surfaceFloat = paper
    /// 内嵌槽 / 轨道（迁移自 surface2）
    static let surface2 = track
    /// 已废弃：原 surface3 仅用于开关关闭态，暂用轨道值
    static let surface3 = track
    /// 边界只负责轻微分层；卡片和窗口主体主要依靠表面色差建立层级。
    static let border = hairline
    /// 已废弃：原 borderStrong，暂用 hairline 值
    static let borderStrong = hairline
    static let separator = hairlineSoft
    static let text = ink
    static let text2 = slate
    static let text3 = ash

    // 平台 / 品牌色（保持不变式；图标与主色不动）
    static let codex = dynamic("#5B6F8D", "#6C82A3")
    static let codexDeep = dynamic("#4C607D", "#8296B5")
    /// 已废弃：彩色柔底，阶段 3 统一清理
    static let codexSoft = dynamic("#E7EBF1", "#28323E")
    // Claude 官方品牌橙；图标在深浅色外观中均保持品牌原色。
    static let claude = Color(hex: "#D97757")
    static let claudeDeep = dynamic("#B85C3B", "#E68A6D")
    /// 已废弃：彩色柔底
    static let claudeSoft = dynamic("#F3E8E3", "#382D2A")
    static let claudeCode = dynamic("#77678B", "#8C7BA3")
    /// 已废弃：彩色柔底
    static let claudeCodeSoft = dynamic("#ECE8EF", "#302B38")
    static let deepseek = dynamic("#5D858D", "#6F98A0")
    /// 已废弃：彩色柔底
    static let deepseekSoft = dynamic("#E8EDFF", "#252D40")
    static let workbuddy = dynamic("#5E8975", "#78A18F")
    /// 已废弃：彩色柔底
    static let workbuddySoft = dynamic("#E4EFEA", "#293A34")
    static let modelFallback = dynamic("#8B877F", "#A5A19A")

    // 状态色（DESIGN §7：三态压缩）
    /// 正常 = 幽灵灰（slate）
    static let ok = slate
    /// 正常状态底色（过渡：雾灰静面，阶段 3 收敛为无底色文字）
    static let okSoft = mist
    /// 偏低 / 注意 = 桃底棕字（warn 为文字色，深色档用 chartAccent 保证可读）
    static let warn = dynamic("#5D2A1A", "#B38668")
    /// 偏低状态底色 = 桃面
    static let warnSoft = peach
    /// 危急文字 = 亮陶红（墨底 / 白底上均保证可读）
    static let danger = dynamic("#C05B3E", "#DF9A7A")
    /// 危急状态底色 = 恒深墨底（深浅模式均为深底，实现"墨底 + 亮字"）
    static let dangerSoft = dynamic("#17191C", "#1B1C20")

    // 图表网格线（迁移自 grid）
    static let grid = hairline
    static let shadowSmall = Color.black.opacity(0.12)
    static let shadow = Color.black.opacity(0.10)

    /// 平台与模型共用的分类色板（5 色）。
    /// 浅色模式带可辨识的低饱和色相（墨 / 陶 / 灰蓝 / 灰紫蓝 / 暖卡其），避免整体沦为黑白灰；
    /// 深色模式档位 1 最亮（Codex 为羊皮纸白，与既有验收一致）。
    /// 状态色（ok/warn/danger）不纳入分类色板；平台徽标请直接用 codex/claude 等品牌色。
    static let categoryPalette: [Color] = [
        chartPrimary,                                        // 0 墨
        chartAccent,                                         // 1 陶
        dynamic("#6C7A92", "#9CA8BA"),                       // 2 雾灰·灰蓝
        dynamic("#8E97A3", "#6E7885"),                       // 3 烟灰·灰紫蓝
        dynamic("#BFA48E", "#B08C6E")                        // 4 沙·暖卡其
    ]

    /// 25 色扩展：5 色系 × 5 明度档（索引 0–4 与 categoryPalette 一致）。
    /// 柱子 / hover 标签 / 排行卡共用同一索引，保证同一平台或模型的颜色处处一致。
    /// 深色模式档位 1 最亮 → 档位 5 最暗；浅色模式档位 1 最深 → 档位 5 最浅。
    static let categoryPaletteExtended: [Color] = categoryPalette + [
        // 档 2
        dynamic("#2E3138", "#B7B4AD"),                       // 5 墨
        dynamic("#82482F", "#9A7159"),                       // 6 陶
        dynamic("#8797AC", "#7E8A99"),                       // 7 雾灰
        dynamic("#A4ACB7", "#5C6570"),                       // 8 烟灰
        dynamic("#D0BBAA", "#8F7763"),                       // 9 沙
        // 档 3
        dynamic("#4C5058", "#8F8D87"),                       // 10 墨
        dynamic("#A86A4E", "#7D5A47"),                       // 11 陶
        dynamic("#A3B1C4", "#636E7C"),                       // 12 雾灰
        dynamic("#BAC1CA", "#49515B"),                       // 13 烟灰
        dynamic("#E0D1C4", "#6F5B4B"),                       // 14 沙
        // 档 4
        dynamic("#7A7E86", "#66655F"),                       // 15 墨
        dynamic("#CC9177", "#614534"),                       // 16 陶
        dynamic("#C0CBD9", "#49525E"),                       // 17 雾灰
        dynamic("#D0D5DC", "#373E46"),                       // 18 烟灰
        dynamic("#EDE4DA", "#524235"),                       // 19 沙
        // 档 5
        dynamic("#A8ABB1", "#3F3E3A"),                       // 20 墨
        dynamic("#E6C1AF", "#463124"),                       // 21 陶
        dynamic("#DCE3EC", "#323A44"),                       // 22 雾灰
        dynamic("#E5E8EC", "#262C33"),                       // 23 烟灰
        dynamic("#F7F1EA", "#382D24")                        // 24 沙
    ]

    /// 浮层提示（tooltip）：比浮卡提亮一档 + 提亮描边，深色模式下与画布保持区分
    static let tooltipSurface = dynamic("#FFFFFF", "#1E1F24")
    static let tooltipBorder = dynamic("#ECECEC", "#3A3B3F")
    /// 侧栏选中项：浅色白纸 / 深色亮灰（比侧栏 mist 提亮一档），配合左侧指示条保证选中明显
    static let sidebarSelected = dynamic("#FFFFFF", "#26282E")

    static func modelColor(for model: String) -> Color {
        let hash = model.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return categoryPalette[Int(hash % UInt32(categoryPalette.count))]
    }
}
