import AppKit
import SwiftUI

// MARK: - 控件

enum PanelSegmentedMetrics {
    static let segmentWidth: CGFloat = 60
    static let height: CGFloat = 26
    static let cornerRadius: CGFloat = 6
}

struct PanelSegmentedControl<Option: Hashable>: View {

    let options: [Option]
    @Binding var selection: Option
    let isEnabled: (Option) -> Bool
    let disabledHelp: ((Option) -> String)?
    let label: (Option) -> String

    @Namespace private var selectionIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        options: [Option],
        selection: Binding<Option>,
        isEnabled: @escaping (Option) -> Bool = { _ in true },
        disabledHelp: ((Option) -> String)? = nil,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        _selection = selection
        self.isEnabled = isEnabled
        self.disabledHelp = disabledHelp
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let enabled = isEnabled(option)
                Button {
                    guard enabled, selection != option else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        selection = option
                    }
                } label: {
                    ZStack {
                        if selection == option {
                            Capsule()
                                .fill(PanelTheme.surface)
                                .frame(width: PanelSegmentedMetrics.segmentWidth, height: PanelSegmentedMetrics.height)
                                .shadow(color: PanelTheme.shadowSmall, radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selection", in: selectionIndicator)
                        }
                        Text(label(option))
                            .font(.system(size: 11, weight: selection == option ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(
                                enabled
                                    ? (selection == option ? PanelTheme.text : PanelTheme.text2)
                                    : PanelTheme.text3
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: PanelSegmentedMetrics.segmentWidth, height: PanelSegmentedMetrics.height)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
                .help(enabled ? "" : (disabledHelp?(option) ?? ""))
            }
        }
        .padding(2)
        .background(PanelTheme.surface2, in: Capsule())
    }
}

// MARK: - 图表提示

private struct ChartTooltipItem: Identifiable {
    let label: String
    let value: String
    let color: Color

    var id: String { label }
}

private struct ChartTooltipSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct ChartTooltipLayout: Layout {
    // Measure the rendered SwiftUI content instead of estimating text widths
    // with AppKit fonts. This keeps the tooltip adaptive while ensuring that
    // labels are truncated only when the real content exceeds the 350pt cap.
    static let minimumWidth: CGFloat = 140
    static let maximumWidth: CGFloat = 350
    static let initialSize = CGSize(width: minimumWidth, height: 46)

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let idealSize = content.sizeThatFits(.unspecified)
        let width = min(max(ceil(idealSize.width), Self.minimumWidth), Self.maximumWidth)
        let fittedSize = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: ceil(fittedSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let content = subviews.first else { return }
        content.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

private struct ChartTooltip: View {
    let title: String
    let value: String
    let valueLabel: String?
    let items: [ChartTooltipItem]

    init(title: String, value: String, valueLabel: String?, items: [ChartTooltipItem] = []) {
        self.title = title
        self.value = value
        self.valueLabel = valueLabel
        self.items = items
    }

    var body: some View {
        ChartTooltipLayout {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text2)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(value)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if !items.isEmpty {
                    Rectangle()
                        .fill(PanelTheme.separator)
                        .frame(height: 1)
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            HStack(alignment: .center, spacing: 6) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(PanelTheme.text2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                Spacer(minLength: 4)
                                Text(item.value)
                                    .font(.system(size: 9, design: .monospaced))
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(PanelTheme.text)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                } else if let valueLabel {
                    Text(valueLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ChartTooltipSizePreferenceKey.self, value: proxy.size)
            }
        }
        // 浮动浮层：实色浮卡面 + 描边 + 投影。
        .background(PanelTheme.tooltipSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PanelTheme.tooltipBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
        .zIndex(20)
        .allowsHitTesting(false)
    }
}

// MARK: - 图表交互状态

struct ChartSelectionState: Equatable {
    private(set) var index: Int?
    private(set) var isPinned = false

    mutating func hover(_ index: Int?) {
        guard !isPinned else { return }
        self.index = index
    }

    mutating func endHover() {
        if !isPinned { index = nil }
    }

    mutating func clear() {
        index = nil
        isPinned = false
    }

    mutating func move(by delta: Int, count: Int) {
        guard count > 0 else { return }
        let current = index ?? (delta > 0 ? -1 : count)
        index = max(0, min(count - 1, current + delta))
    }

    mutating func togglePin(count: Int) {
        guard count > 0 else { return }
        if index == nil { index = 0 }
        isPinned.toggle()
    }
}

struct ChartInteractionState: Equatable {
    var selection = ChartSelectionState()
    var tooltipSize = ChartTooltipLayout.initialSize
}

struct StackedBarChart: View {
    let rows: [MainPanelView.TokenChartRow]
    let todayLabel: String
    let tokenLabel: String
    let language: AppLanguage
    let showsSingleSegmentBreakdown: Bool
    @State private var interaction = ChartInteractionState()

    init(
        rows: [MainPanelView.TokenChartRow],
        todayLabel: String,
        tokenLabel: String,
        language: AppLanguage = .simplifiedChinese,
        showsSingleSegmentBreakdown: Bool = false
    ) {
        self.rows = rows
        self.todayLabel = todayLabel
        self.tokenLabel = tokenLabel
        self.language = language
        self.showsSingleSegmentBreakdown = showsSingleSegmentBreakdown
    }

    var body: some View {
        GeometryReader { proxy in
            let peak = max(rows.map(\.total).max() ?? 1, 1)
            let plotTopInset: CGFloat = 15
            let plotBottomInset: CGFloat = 2
            let plotHeight = max(proxy.size.height - plotTopInset - plotBottomInset, 1)
            let plotX: CGFloat = 44
            let plotWidth = max(proxy.size.width - 52, 1)
            let slotWidth = plotWidth / CGFloat(max(rows.count, 1))
            let barWidth = min(20, max(slotWidth * 0.6, 0.65))
            let plot = CGRect(x: plotX, y: plotTopInset, width: plotWidth, height: plotHeight)
            let barGeometries = rows.enumerated().map { index, row in
                let slotX = plot.minX + CGFloat(index) * slotWidth
                return StackedBarGeometry.make(
                    values: row.segments.map(\.value),
                    peak: peak,
                    plot: plot,
                    barX: slotX + (slotWidth - barWidth) / 2,
                    barWidth: barWidth,
                    hoverX: slotX + 2,
                    hoverWidth: slotWidth - 4
                )
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for line in 0...3 {
                        let y = plot.minY + plot.height * CGFloat(line) / 3
                        var path = Path()
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        context.stroke(
                            path,
                            with: .color(PanelTheme.grid),
                            style: StrokeStyle(lineWidth: 1, dash: line == 3 ? [] : [4, 4])
                        )
                    }

                    guard !rows.isEmpty else { return }
                    for (index, row) in rows.enumerated() {
                        let geometry = barGeometries[index]
                        for (segmentIndex, segment) in row.segments.enumerated() {
                            let rect = geometry.segmentRects[segmentIndex]
                            guard rect.height > 0 else { continue }
                            let isEmphasized = interaction.selection.index == nil || interaction.selection.index == index
                            let color = segment.color.opacity(isEmphasized ? 1 : 0.42)
                            let radius = min(2, min(barWidth / 2, rect.height / 2))
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: radius),
                                with: .color(color)
                            )
                            var separator = Path()
                            separator.move(to: CGPoint(x: rect.minX, y: rect.minY))
                            separator.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                            context.stroke(separator, with: .color(PanelTheme.surface.opacity(0.78)), lineWidth: 0.75)
                        }
                        if interaction.selection.index == index {
                            context.stroke(
                                Path(roundedRect: geometry.barRect, cornerRadius: min(2, barWidth / 2)),
                                with: .color(PanelTheme.text.opacity(0.34)),
                                lineWidth: 1
                            )
                        }
                    }
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(QuotaFormatters.localizedTokens(peak, language: language))
                    Spacer()
                    Text(QuotaFormatters.localizedTokens(peak * 2 / 3, language: language))
                    Spacer()
                    Text(QuotaFormatters.localizedTokens(peak / 3, language: language))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 8.5, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text3)
                .frame(width: 32, height: plotHeight, alignment: .topTrailing)
                .position(x: 16, y: plotTopInset + plotHeight / 2)

                if let selectedIndex = interaction.selection.index, rows.indices.contains(selectedIndex) {
                    let row = rows[selectedIndex]
                    let detailSegments = row.segments.filter { $0.name != tokenLabel }
                    let tooltipItems = (detailSegments.count > 1 || showsSingleSegmentBreakdown)
                        ? compactTooltipItems(detailSegments)
                        : []
                    let tooltipCenter = ChartTooltipPlacement.adjacentToBar(
                        barRect: barGeometries[selectedIndex].barRect,
                        tooltipSize: interaction.tooltipSize,
                        containerSize: proxy.size
                    )
                    ChartTooltip(
                        title: row.isToday ? todayLabel : row.label,
                        value: QuotaFormatters.localizedTokens(row.total, language: language),
                        valueLabel: tooltipItems.isEmpty ? nil : tokenLabel,
                        items: tooltipItems
                    )
                    .position(x: tooltipCenter.x, y: tooltipCenter.y)
                }
            }
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language == .simplifiedChinese ? "Token 趋势图" : "Token trend chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction { direction in
                interaction.selection.move(by: direction == .increment ? 1 : -1, count: rows.count)
            }
            .onKeyPress(.return) {
                interaction.selection.togglePin(count: rows.count)
                return .handled
            }
            .onKeyPress(.space) {
                interaction.selection.togglePin(count: rows.count)
                return .handled
            }
            .onMoveCommand { direction in
                switch direction {
                case .left: interaction.selection.move(by: -1, count: rows.count)
                case .right: interaction.selection.move(by: 1, count: rows.count)
                default: break
                }
            }
            .onExitCommand { interaction.selection.clear() }
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { interaction.tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    interaction.selection.hover(index(at: location, plotX: plotX, plotWidth: plotWidth))
                case .ended:
                    interaction.selection.endHover()
                @unknown default:
                    interaction.selection.endHover()
                }
            }
        }
    }

    private func compactTooltipItems(
        _ segments: [MainPanelView.TokenChartSegment]
    ) -> [ChartTooltipItem] {
        let colors = Dictionary(
            segments.map { ($0.id, $0.color) },
            uniquingKeysWith: { first, _ in first }
        )
        return ChartTooltipBreakdown.compact(
            segments.map {
                ChartTooltipBreakdownEntry(id: $0.id, label: $0.name, value: $0.value)
            }
        ).map { entry in
            ChartTooltipItem(
                label: entry.hiddenItemCount > 0
                    ? otherItemsLabel(entry.hiddenItemCount)
                    : entry.label,
                value: QuotaFormatters.localizedTokens(entry.value, language: language),
                color: entry.hiddenItemCount > 0
                    ? PanelTheme.chartDim
                    : (colors[entry.id] ?? PanelTheme.chartDim)
            )
        }
    }

    private func otherItemsLabel(_ count: Int) -> String {
        language == .simplifiedChinese ? "其他 \(count) 项" : "\(count) other items"
    }

    private var accessibilitySummary: String {
        guard let index = interaction.selection.index, rows.indices.contains(index) else {
            return language == .simplifiedChinese ? "聚焦后按左右键查看每日 Token，按 Enter 或空格固定选择" : "Focus the chart, use left or right arrows to inspect each day, then press Enter or Space to pin the selection"
        }
        let row = rows[index]
        let details = row.segments
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { "\($0.name) \(QuotaFormatters.localizedTokens($0.value, language: language))" }
            .joined(separator: " · ")
        let detailText = details.isEmpty ? "" : (language == .simplifiedChinese ? "，分类：\(details)" : ", categories: \(details)")
        let pinned = interaction.selection.isPinned ? (language == .simplifiedChinese ? "，已固定" : ", pinned") : ""
        return "\(row.label), \(QuotaFormatters.localizedTokens(row.total, language: language))\(detailText)\(pinned)"
    }

    private func index(at location: CGPoint, plotX: CGFloat, plotWidth: CGFloat) -> Int? {
        guard !rows.isEmpty, location.x >= plotX, location.x <= plotX + plotWidth else { return nil }
        let slotWidth = plotWidth / CGFloat(rows.count)
        return min(max(Int((location.x - plotX) / slotWidth), 0), rows.count - 1)
    }

}

struct TokenYearHeatmap: View {
    let levels: [Int]
    let values: [Int]
    let labels: [String]
    let leadingOffset: Int
    let language: AppLanguage
    @State private var interaction = ChartInteractionState()

    init(
        levels: [Int],
        values: [Int] = [],
        labels: [String] = [],
        leadingOffset: Int,
        language: AppLanguage = .simplifiedChinese
    ) {
        self.levels = levels
        self.values = values
        self.labels = labels
        self.leadingOffset = leadingOffset
        self.language = language
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = cellMetrics(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for (index, level) in levels.enumerated() {
                        let cell = CalendarHeatmapLayout.cell(forDayAt: index, leadingOffset: leadingOffset)
                        guard cell.column < 53 else { continue }
                        let rect = CGRect(
                            x: CGFloat(cell.column) * (metrics.cellWidth + metrics.gap),
                            y: CGFloat(cell.row) * (metrics.cellHeight + metrics.gap),
                            width: metrics.cellWidth,
                            height: metrics.cellHeight
                        )
                        let path = Path(roundedRect: rect, cornerRadius: min(2, min(metrics.cellWidth / 2, metrics.cellHeight / 2)))
                        context.fill(path, with: .color(PanelTheme.heatColor(level: level)))
                    }
                }
                if let selectedIndex = interaction.selection.index,
                   values.indices.contains(selectedIndex),
                   labels.indices.contains(selectedIndex) {
                    let cell = CalendarHeatmapLayout.cell(forDayAt: selectedIndex, leadingOffset: leadingOffset)
                    let anchorX = CGFloat(cell.column) * (metrics.cellWidth + metrics.gap) + metrics.cellWidth / 2
                    let anchorY = CGFloat(cell.row) * (metrics.cellHeight + metrics.gap) + metrics.cellHeight / 2
                    ChartTooltip(
                        title: labels[selectedIndex],
                        value: QuotaFormatters.localizedTokens(values[selectedIndex], language: language),
                        valueLabel: nil
                    )
                    .position(
                        x: ChartTooltipPlacement.x(
                            anchorX: anchorX,
                            tooltipWidth: interaction.tooltipSize.width,
                            containerWidth: proxy.size.width
                        ),
                        y: ChartTooltipPlacement.y(
                            anchorY: anchorY,
                            tooltipHeight: interaction.tooltipSize.height,
                            containerHeight: proxy.size.height
                        )
                    )
                }
            }
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language == .simplifiedChinese ? "年度 Token 热力图" : "Yearly token heatmap")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction { direction in
                interaction.selection.move(by: direction == .increment ? 1 : -1, count: values.count)
            }
            .onKeyPress(.return) {
                interaction.selection.togglePin(count: values.count)
                return .handled
            }
            .onKeyPress(.space) {
                interaction.selection.togglePin(count: values.count)
                return .handled
            }
            .onMoveCommand { direction in
                switch direction {
                case .left: interaction.selection.move(by: -1, count: values.count)
                case .right: interaction.selection.move(by: 1, count: values.count)
                default: break
                }
            }
            .onExitCommand { interaction.selection.clear() }
            .onPreferenceChange(ChartTooltipSizePreferenceKey.self) { interaction.tooltipSize = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    interaction.selection.hover(index(at: location, metrics: metrics))
                case .ended:
                    interaction.selection.endHover()
                @unknown default:
                    interaction.selection.endHover()
                }
            }
        }
    }

    private struct CellMetrics {
        let gap: CGFloat
        let cellWidth: CGFloat
        let cellHeight: CGFloat
    }

    private func cellMetrics(in size: CGSize) -> CellMetrics {
        let gap: CGFloat = 3
        return CellMetrics(
            gap: gap,
            cellWidth: max((size.width - gap * 52) / 53, 1),
            cellHeight: max((size.height - gap * 6) / 7, 1)
        )
    }

    private func index(at location: CGPoint, metrics: CellMetrics) -> Int? {
        let columnStep = metrics.cellWidth + metrics.gap
        let rowStep = metrics.cellHeight + metrics.gap
        let column = Int(location.x / columnStep)
        let row = Int(location.y / rowStep)
        guard column >= 0, column < 53, row >= 0, row < 7 else { return nil }
        guard location.x.truncatingRemainder(dividingBy: columnStep) <= metrics.cellWidth,
              location.y.truncatingRemainder(dividingBy: rowStep) <= metrics.cellHeight else { return nil }
        let index = column * 7 + row - leadingOffset
        return values.indices.contains(index) ? index : nil
    }

    private var accessibilitySummary: String {
        guard let index = interaction.selection.index, values.indices.contains(index), labels.indices.contains(index) else {
            return language == .simplifiedChinese ? "聚焦后按左右键查看每日 Token，按 Enter 或空格固定选择" : "Focus the heatmap, use left or right arrows to inspect each day, then press Enter or Space to pin the selection"
        }
        let pinned = interaction.selection.isPinned ? (language == .simplifiedChinese ? "，已固定" : ", pinned") : ""
        return "\(labels[index]), \(QuotaFormatters.localizedTokens(values[index], language: language))\(pinned)"
    }

}
