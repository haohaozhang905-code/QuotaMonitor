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
/// - 仍有调用方的旧语义名称按迁移表映射到新语义色；未使用的旧 token 不保留
/// - 新增语义 token（bg/ink/paper/mist/fog/…/chart*/heat*）供后续阶段使用
/// - 已废弃语义仅保留仍有调用方的过渡值，阶段 3 清理
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

    static func heatColor(level: Int) -> Color {
        switch level {
        case 1: heat1
        case 2: heat2
        case 3: heat3
        case 4: heat4
        default: heat0
        }
    }

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

    // 下拉框覆盖在不断变化的桌面背景上，需要比主面板正文更稳定的前景对比度。
    // 深色档参考系统电池面板：主文字接近白色，次级文字保持清晰的中灰层级。
    static let dropdownText = dynamic("#17191C", "#F2F3F5")
    static let dropdownTextSecondary = dynamic("#656A73", "#C3C5CC")

    // 平台 / 品牌色（保持不变式；图标与主色不动）
    static let codex = dynamic("#5B6F8D", "#6C82A3")
    // Claude 官方品牌橙；图标在深浅色外观中均保持品牌原色。
    static let claude = Color(hex: "#D97757")
    static let claudeCode = dynamic("#77678B", "#8C7BA3")
    static let deepseek = dynamic("#5D858D", "#6F98A0")
    static let workbuddy = dynamic("#5E8975", "#78A18F")
    static let modelFallback = dynamic("#8B877F", "#A5A19A")

    // 状态色（正常 / 关注 / 危急），浅色和深色各自配对底色。
    /// 正常使用绿色，保证状态标签一眼可识别。
    static let ok = dynamic("#238636", "#65D27F")
    static let success = ok
    static let okSoft = dynamic("#E8F5EC", "#213126")
    /// 需要关注：暖桃色文字配浅桃底。
    static let warn = dynamic("#8A4B08", "#F0B35D")
    static let warnSoft = dynamic("#FFF1E4", "#3B2A20")
    /// 危急：红色文字配浅红底，避免浅色模式出现黑底红字。
    static let danger = dynamic("#B42318", "#FF9B85")
    static let dangerSoft = dynamic("#FDE8E5", "#3A2420")

    static func quotaValueColor(_ health: QuotaHealth) -> Color {
        switch health {
        case .healthy, .unknown: text
        case .warning: warn
        case .critical: danger
        }
    }

    static func dropdownQuotaValueColor(_ health: QuotaHealth) -> Color {
        switch health {
        case .healthy, .unknown: dropdownText
        case .warning: warn
        case .critical: danger
        }
    }

    // 图表网格线（迁移自 grid）
    static let grid = hairline
    static let shadowSmall = Color.black.opacity(0.12)
    static let shadow = Color.black.opacity(0.10)

    /// 平台与模型共用 Steep c1–c5。超过五类时允许稳定复用，
    /// 但不再为柱图引入额外色相或明度档。
    static let categoryPalette: [Color] = [
        chartPrimary,
        chartAccent,
        chartNeutral,
        chartDim,
        chartSand
    ]

    /// 浮层提示（tooltip）：比浮卡提亮一档 + 提亮描边，深色模式下与画布保持区分
    static let tooltipSurface = dynamic("#FFFFFF", "#1E1F24")
    static let tooltipBorder = dynamic("#ECECEC", "#3A3B3F")
    /// 侧栏选中项：浅色白纸 / 深色亮灰（比侧栏 mist 提亮一档），配合左侧指示条保证选中明显
    static let sidebarSelected = dynamic("#FFFFFF", "#26282E")

}

/// 系统材质负责实时取样与模糊；透明度和颜色随 macOS 外观及辅助功能设置变化。
struct PanelVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    /// 从不接收 key 状态的浮层（下拉面板）保持 active，避免材质随应用失焦冻结观感。
    var keepsActiveState = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        if keepsActiveState {
            view.state = .active
        }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // 页面切换会触发 SwiftUI 更新 NSViewRepresentable。重复写入相同材质会让
        // NSVisualEffectView 短暂重建采样层，在浅色侧栏上表现为一次闪白。
        if view.material != material {
            view.material = material
        }
        if view.blendingMode != blendingMode {
            view.blendingMode = blendingMode
        }
        let targetState: NSVisualEffectView.State = keepsActiveState ? .active : .followsWindowActiveState
        if view.state != targetState {
            view.state = targetState
        }
    }
}

/// 统一半透明玻璃表面：系统材质负责取样模糊，主题色调薄层保证文字对比。
/// 开启“减少透明度”时整体回退到调用方提供的实色。
struct GlassSurface: View {
    let material: NSVisualEffectView.Material
    let tint: Color
    let opaqueFallback: Color
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var keepsActiveState = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            opaqueFallback
        } else {
            PanelVisualEffect(material: material, blendingMode: blendingMode, keepsActiveState: keepsActiveState)
                .overlay(tint)
        }
    }
}
