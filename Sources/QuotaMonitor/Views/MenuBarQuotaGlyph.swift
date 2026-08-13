import AppKit
import SwiftUI

struct MenuBarQuotaGlyph: View {
    var body: some View {
        Image(nsImage: Self.templateImage)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }

    /// 供 NSStatusItem 按钮直接使用：优先用与小组件同款的小图标。
    static var image: NSImage { cachedImage }

    private static let cachedImage: NSImage = {
        if let url = QuotaResourceBundle.current.url(forResource: "menubar-icon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return templateImage
    }()

    private static let templateImage: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let upperArc = NSBezierPath()
            upperArc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: 6.2,
                startAngle: 18,
                endAngle: 166
            )
            upperArc.lineWidth = 2.15
            upperArc.lineCapStyle = .round
            upperArc.stroke()

            let lowerArc = NSBezierPath()
            lowerArc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: 6.2,
                startAngle: 198,
                endAngle: 346
            )
            lowerArc.lineWidth = 2.15
            lowerArc.lineCapStyle = .round
            lowerArc.stroke()

            NSBezierPath(ovalIn: NSRect(x: 7.35, y: 7.35, width: 3.3, height: 3.3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}


/// 启动读取态：借鉴 Wi-Fi 连接中的逐层扩散，沿用 QuotaMonitor 的中心点与双弧语言。
struct MenuBarLoadingGlyph: View {
    let phase: Int

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 1)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2)),
                with: .color(.white)
            )
            for level in 0..<2 {
                let radius = CGFloat(4.2 + Double(level) * 3.2)
                let opacity = level <= phase % 3 ? 1.0 : 0.22
                var upper = Path()
                upper.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(205),
                    endAngle: .degrees(335),
                    clockwise: false
                )
                var lower = Path()
                lower.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(25),
                    endAngle: .degrees(155),
                    clockwise: false
                )
                context.stroke(
                    upper,
                    with: .color(.white.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                context.stroke(
                    lower,
                    with: .color(.white.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("QuotaMonitor loading")
    }
}
