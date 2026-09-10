import CoreGraphics

struct StackedBarGeometry: Equatable, Sendable {
    let barRect: CGRect
    let segmentRects: [CGRect]
    let hoverRect: CGRect

    static func make(
        values: [Int],
        peak: Int,
        plot: CGRect,
        barX: CGFloat,
        barWidth: CGFloat,
        hoverX: CGFloat,
        hoverWidth: CGFloat,
        minimumSegmentHeight: CGFloat = 1,
        hoverTopPadding: CGFloat = 3
    ) -> Self {
        let positiveIndices = values.indices.filter { values[$0] > 0 }
        let total = positiveIndices.reduce(0) { $0 + values[$1] }
        guard total > 0, peak > 0, plot.height > 0 else {
            let empty = CGRect(x: barX, y: plot.maxY, width: barWidth, height: 0)
            return .init(
                barRect: empty,
                segmentRects: Array(repeating: empty, count: values.count),
                hoverRect: CGRect(x: hoverX, y: plot.maxY, width: hoverWidth, height: 0)
            )
        }

        let targetHeight = min(
            max(CGFloat(total) / CGFloat(peak) * plot.height, min(1, plot.height)),
            plot.height
        )
        let baseHeight = min(minimumSegmentHeight, targetHeight / CGFloat(positiveIndices.count))
        let distributableHeight = max(targetHeight - baseHeight * CGFloat(positiveIndices.count), 0)
        var heights = Array(repeating: CGFloat.zero, count: values.count)
        var assignedHeight: CGFloat = 0
        for (offset, index) in positiveIndices.enumerated() {
            let height: CGFloat
            if offset == positiveIndices.count - 1 {
                height = max(targetHeight - assignedHeight, 0)
            } else {
                height = baseHeight + distributableHeight * CGFloat(values[index]) / CGFloat(total)
            }
            heights[index] = height
            assignedHeight += height
        }

        var bottom = plot.maxY
        var rects = Array(
            repeating: CGRect(x: barX, y: plot.maxY, width: barWidth, height: 0),
            count: values.count
        )
        for index in values.indices where heights[index] > 0 {
            let rect = CGRect(x: barX, y: bottom - heights[index], width: barWidth, height: heights[index])
            rects[index] = rect
            bottom = rect.minY
        }

        let barRect = CGRect(x: barX, y: bottom, width: barWidth, height: plot.maxY - bottom)
        let hoverTop = max(plot.minY, barRect.minY - hoverTopPadding)
        let hoverRect = CGRect(
            x: hoverX,
            y: hoverTop,
            width: max(hoverWidth, 1),
            height: max(plot.maxY - hoverTop, 0)
        )
        return .init(barRect: barRect, segmentRects: rects, hoverRect: hoverRect)
    }
}
