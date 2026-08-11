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
    static var image: NSImage {
        if let url = QuotaResourceBundle.current.url(forResource: "menubar-icon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return templateImage
    }

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
