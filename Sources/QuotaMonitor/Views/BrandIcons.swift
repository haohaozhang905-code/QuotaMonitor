import SwiftUI

// MARK: - 品牌图标

/// 产品图标枚举：Codex / Claude / Claude Code / DeepSeek / WorkBuddy。
enum BrandIconKind: String, Sendable {
    case codex
    case claude
    case claudeCode
    case deepSeek
    case workBuddy
}

/// 统一入口：按品牌渲染官方图标（单色模板或官方配色）。
struct BrandIconView: View {
    let kind: BrandIconKind
    var size: CGFloat = 14
    var monochromeColor: Color? = nil

    var body: some View {
        Group {
            if let monochromeColor {
                monochromeColor
                    .mask(iconBody)
            } else {
                iconBody
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconBody: some View {
        switch kind {
        case .codex: CodexBrandIcon(size: size)
        case .claude: ClaudeBrandIcon(size: size)
        case .claudeCode: ClaudeCodeBrandIcon(size: size)
        case .deepSeek: DeepSeekBrandIcon(size: size)
        case .workBuddy: WorkBuddyBrandIcon(size: size)
        }
    }
}

/// 带缓存的 SVG 品牌路径（只解析一次，Swift 6 下显式标注为非隔离常量）。
private enum BrandPaths {
    nonisolated(unsafe) static let codex = SVGPath.cgPath(from: BrandIconPaths.codex)
    nonisolated(unsafe) static let claude = SVGPath.cgPath(from: BrandIconPaths.claude)
    nonisolated(unsafe) static let claudeCode = SVGPath.cgPath(from: BrandIconPaths.claudeCode)
    nonisolated(unsafe) static let deepSeek = SVGPath.cgPath(from: BrandIconPaths.deepSeek)
    nonisolated(unsafe) static let workBuddy = SVGPath.cgPath(from: BrandIconPaths.workBuddy)
}

private struct BrandShape: Shape {
    /// CGPath 不可变且仅作读取，用 @unchecked Sendable 包装以通过 Swift 6 并发检查。
    private struct PathBox: @unchecked Sendable {
        let value: CGPath
    }

    private let box: PathBox
    let viewBox: CGFloat

    init(path: CGPath, viewBox: CGFloat) {
        self.box = PathBox(value: path)
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        var path = Path(box.value)
        path = path.applying(
            CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: (rect.width - viewBox * scale) / 2, y: (rect.height - viewBox * scale) / 2)
        )
        return path
    }
}

// MARK: - 各品牌图标

/// Codex：App 内沿用原有蓝紫品牌渐变；菜单栏图标由 MenuBarQuotaGlyph 单独管理。
private struct CodexBrandIcon: View {
    let size: CGFloat
    var body: some View {
        BrandShape(path: BrandPaths.codex, viewBox: 24)
            .fill(
                LinearGradient(
                    colors: [
                        PanelTheme.dynamic("#B1A7FF", "#BFC2FF"),
                        PanelTheme.dynamic("#7A9DFF", "#8A97FF"),
                        PanelTheme.dynamic("#3941FF", "#6B78F2")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Claude：官方星芒标，暖橙色。
private struct ClaudeBrandIcon: View {
    let size: CGFloat
    var body: some View {
        BrandShape(path: BrandPaths.claude, viewBox: 24)
            .fill(PanelTheme.claude)
    }
}

/// Claude Code：官方终端括号标，用独立紫色与 Claude 的暖橙色区分。
private struct ClaudeCodeBrandIcon: View {
    let size: CGFloat
    var body: some View {
        BrandShape(path: BrandPaths.claudeCode, viewBox: 24)
            .fill(PanelTheme.claudeCode)
    }
}

/// DeepSeek：官方蓝鲸。
private struct DeepSeekBrandIcon: View {
    let size: CGFloat
    var body: some View {
        BrandShape(path: BrandPaths.deepSeek, viewBox: 24)
            .fill(PanelTheme.deepseek)
    }
}

/// WorkBuddy：绿色圆形标（绿渐变圆 + 白色 W + 薄荷辉光）。
private struct WorkBuddyBrandIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PanelTheme.dynamic("#37E2BE", "#3BD6A8"), PanelTheme.dynamic("#15B687", "#17C08F")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            // 两个薄荷辉光圆（近似官方模糊效果）。
            Circle()
                .fill(PanelTheme.dynamic("#B6FBE6", "#2E5A4C").opacity(0.55))
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: -size * 0.22, y: size * 0.36)
                .blur(radius: size * 0.12)
            Circle()
                .fill(PanelTheme.dynamic("#B6FBE6", "#2E5A4C").opacity(0.7))
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(x: size * 0.3, y: size * 0.48)
                .blur(radius: size * 0.10)
            // W 主体 + 两个小点缀。
            BrandShape(path: BrandPaths.workBuddy, viewBox: 40)
                .fill(.white)
            WorkBuddySparkRects(size: size)
        }
        // W 路径在官方文件里超出视框，依赖圆形容器裁剪。
        .clipShape(Circle())
    }
}

/// WorkBuddy 官方标志里的两个白色小圆角条（旋转 -30°）。
private struct WorkBuddySparkRects: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            spark
                .offset(x: -0.053 * size, y: 0.355 * size)
            spark
                .offset(x: 0.2175 * size, y: 0.1985 * size)
        }
    }

    private var spark: some View {
        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
            .fill(.white)
            .frame(width: size * 0.10, height: size * 0.208)
            .rotationEffect(.degrees(-30))
    }
}

// MARK: - 便捷引用

extension BrandIconKind {
    /// 各图标的“主体色”，用于图表/图例配色统一。
    var mainColor: Color {
        switch self {
        case .codex: PanelTheme.codex
        case .claude: PanelTheme.claude
        case .claudeCode: PanelTheme.claudeCode
        case .deepSeek: PanelTheme.deepseek
        case .workBuddy: PanelTheme.workbuddy
        }
    }
}
