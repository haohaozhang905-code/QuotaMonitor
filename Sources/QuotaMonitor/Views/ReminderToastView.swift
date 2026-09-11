import AppKit
import SwiftUI

struct ReminderToastView: View {
    static let cardWidth: CGFloat = 372

    let presentation: ReminderPresentation
    let onOpen: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PanelTheme.text)
                    ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, detail in
                        Text(detail)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(PanelTheme.text2)
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(PanelTheme.text3)
                    .frame(width: 26, height: 26)
                    .background(PanelTheme.surface2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(15)
        .frame(width: Self.cardWidth, alignment: .leading)
        .background(PanelTheme.surfaceFloat)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PanelTheme.hairline, lineWidth: 1)
        }
        // 阴影由窗口提供（NSPanel.hasShadow），不用 SwiftUI shadow：
        // SwiftUI 阴影在透明 NSHostingView 中按视图 bounds 合成，会在圆角卡片外形成一圈灰晕。
        .onHover(perform: onHoverChange)
    }
}
