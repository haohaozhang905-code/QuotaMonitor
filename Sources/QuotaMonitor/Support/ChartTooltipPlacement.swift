import CoreGraphics

/// 所有图表共享的 tooltip 几何规则。保持为纯函数，便于覆盖边缘翻转和夹紧行为。
enum ChartTooltipPlacement {
    static let gap: CGFloat = 10
    static let edgeInset: CGFloat = 6

    static func x(anchorX: CGFloat, tooltipWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let width = max(tooltipWidth, 1)
        let rightEdge = anchorX + gap + width
        if rightEdge <= containerWidth - edgeInset {
            return anchorX + gap + width / 2
        }

        let leftEdge = anchorX - gap - width
        if leftEdge >= edgeInset {
            return anchorX - gap - width / 2
        }

        let rightSpace = containerWidth - edgeInset - (anchorX + gap)
        let leftSpace = anchorX - gap - edgeInset
        let preferred = rightSpace >= leftSpace
            ? anchorX + gap + width / 2
            : anchorX - gap - width / 2
        let minimum = edgeInset + width / 2
        let maximum = max(minimum, containerWidth - edgeInset - width / 2)
        return min(max(preferred, minimum), maximum)
    }

    static func y(anchorY: CGFloat, tooltipHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let halfHeight = max(tooltipHeight, 1) / 2
        let minimum = edgeInset + halfHeight
        let maximum = containerHeight - edgeInset - halfHeight
        guard maximum >= minimum else { return containerHeight / 2 }
        return min(max(anchorY, minimum), maximum)
    }

    /// 与柱顶对齐、右侧优先，放不下时翻到左侧，最终限制在容器边缘内。
    static func adjacentToBar(
        barRect: CGRect,
        tooltipSize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let width = max(tooltipSize.width, 1)
        let height = max(tooltipSize.height, 1)
        let halfWidth = width / 2
        let halfHeight = height / 2
        let minimumX = edgeInset + halfWidth
        let maximumX = max(minimumX, containerSize.width - edgeInset - halfWidth)
        let barGap: CGFloat = 8
        let rightX = barRect.maxX + barGap + halfWidth
        let leftX = barRect.minX - barGap - halfWidth
        let preferredX: CGFloat
        if rightX <= maximumX {
            preferredX = rightX
        } else if leftX >= minimumX {
            preferredX = leftX
        } else {
            let rightSpace = containerSize.width - edgeInset - barRect.maxX
            let leftSpace = barRect.minX - edgeInset
            preferredX = rightSpace >= leftSpace ? rightX : leftX
        }

        let minimumY = edgeInset + halfHeight
        let maximumY = max(minimumY, containerSize.height - edgeInset - halfHeight)
        return CGPoint(
            x: min(max(preferredX, minimumX), maximumX),
            y: min(max(barRect.minY + halfHeight, minimumY), maximumY)
        )
    }
}
