import SwiftUI

extension MainPanelView {
    var tokenPage: some View {
        let dashboard = tokenDashboard
        return VStack(alignment: .leading, spacing: 14) {
            tokenHeading
            tokenMetricStrip(dashboard)
            tokenChartCard()
            tokenRankings(dashboard)
            tokenHeatmapCard
        }
        .onAppear { selectAvailableTokenPeriodIfNeeded() }
    }

    private var tokenHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(language.text("panel.tokensPageTitle"))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .kerning(-0.4)
                .foregroundStyle(PanelTheme.text)
            Spacer(minLength: 8)
            tokenPeriodPicker
        }
        .frame(height: 26, alignment: .center)
    }

    private func tokenMetricStrip(_ dashboard: TokenDashboardSnapshot) -> some View {
        HStack(spacing: 0) {
            metricCell(language.text("tokens.total"), QuotaFormatters.localizedTokens(dashboard.total, language: language.language), large: true)
            metricCell(language.text("tokens.average"), QuotaFormatters.localizedTokens(dashboard.average, language: language.language), large: false)
            metricCell(language.text("tokens.peak"), QuotaFormatters.localizedTokens(dashboard.peak, language: language.language), large: false)
            metricCell(language.text("tokens.topPlatform"), dashboard.platform.first?.name ?? "--", large: false)
            metricCell(language.text("tokens.topModel"), dashboard.models.first?.model ?? "--", large: false)
        }
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricCell(_ label: String, _ value: String, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.text3)
            Text(value)
                .font(.system(size: large ? 21 : 16, weight: .semibold, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .overlay(alignment: .trailing) {
            Rectangle().fill(PanelTheme.separator).frame(width: 0.5, height: 38)
        }
    }

    private func tokenChartCard() -> some View {
        let chart = tokenChartSnapshot()
        let axisIndices = chartAxisIndices(for: chart.rows)
        return panelCard(spacing: 6, topPadding: 10, bottomPadding: 8) {
            // Keep the title and the segmented control on one visual centerline.
            // The whole header starts slightly higher because the control is
            // taller than the title, keeping the title's visible glyphs aligned
            // with the 16pt title inset used by the other cards.
            HStack(alignment: .center, spacing: 10) {
                Text(language.text(tokenChartDimension == .platform ? "panel.tokenTrendPlatformTitle" : "panel.tokenTrendModelTitle"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer(minLength: 6)
                Text(language.text("tokens.peakValue", QuotaFormatters.localizedTokens(chart.rows.map { $0.total }.max() ?? 0, language: language.language)))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text3)
                tokenChartDimensionPicker
            }
            StackedBarChart(
                rows: chart.rows,
                todayLabel: language.text("panel.today"),
                tokenLabel: language.text("panel.totalTokens"),
                language: language.language,
                showsSingleSegmentBreakdown: true
            )
                .frame(height: 140)
                .padding(.top, 1)
                // tooltip 会在趋势图边界外展开；提升整个图表容器，避免下面的图例覆盖浮层。
                .zIndex(10)
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 44, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(axisIndices, id: \.self) { index in
                    let row = chart.rows[index]
                    let x = 44 + (CGFloat(index) + 0.5) / CGFloat(max(chart.rows.count, 1)) * plotWidth
                    Text(row.isToday ? language.text("panel.today") : row.label)
                        .font(.system(size: 8.5, weight: row.isToday ? .semibold : .regular, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(row.isToday ? PanelTheme.codex : PanelTheme.text3)
                        .lineLimit(1)
                        .fixedSize()
                        .position(x: x, y: 5)
                    }
                }
            }
            .frame(height: 10)
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(chart.legend) { item in
                            legendItem(item.color, item.name)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(minWidth: max(proxy.size.width - 4, 0), alignment: .center)
                }
            }
            .frame(height: 18)
            // Leave a clear breathing space between the x-axis tick labels
            // and the secondary legend row.
            .padding(.top, 5)
            if chart.legend.isEmpty {
                Text(language.text("panel.modelNoData"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PanelTheme.text3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func tokenRankings(_ dashboard: TokenDashboardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            rankingCard(title: language.text("tokens.platformUsage"), items: dashboard.platform)
            rankingCard(title: language.text("tokens.modelUsage"), items: modelRankingItems(from: dashboard.models))
        }
    }

    private func modelRankingItems(from rows: [ModelRow]) -> [BreakdownItem] {
        let colors = categoryColors(for: rows.map { row in
            TokenChartCategory(
                id: "model|\(row.model)",
                name: row.model,
                preferredPaletteIndex: UsageBreakdownColor.stableIndex(for: row.model)
            )
        })
        return rows.map {
            BreakdownItem(
                name: $0.model,
                value: $0.total,
                share: $0.share,
                color: colors["model|\($0.model)"] ?? PanelTheme.modelFallback
            )
        }
    }

    private func rankingCard(title: String, items: [BreakdownItem]) -> some View {
        panelCard(height: 170) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 5) {
                ForEach(items.prefix(5)) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 10, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text)
                            .lineLimit(1)
                            .frame(width: 108, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(PanelTheme.surface2)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(item.color)
                                        .frame(width: max(proxy.size.width * item.share, 2))
                                }
                        }
                        .frame(height: 4)
                        Text(QuotaFormatters.localizedTokens(item.value, language: language.language))
                            .font(.system(size: 9, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                            .frame(width: 54, alignment: .trailing)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(height: 17)
                }
                if items.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var tokenHeatmapCard: some View {
        let snapshot = yearHeatmapSnapshot
        return panelCard {
            HStack(alignment: .bottom, spacing: 8) {
                Text(language.text("tokens.yearTitle"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                HStack(spacing: 4) {
                    Text(language.text("tokens.less"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(PanelTheme.heatColor(level: level))
                            .frame(width: 9, height: 9)
                    }
                    Text(language.text("tokens.more"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                }
            }
            GeometryReader { proxy in
                let leadingWidth: CGFloat = 26
                let gap: CGFloat = 3
                let plotWidth = max(proxy.size.width - leadingWidth, 1)
                let cellWidth = max((plotWidth - gap * 52) / 53, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(snapshot.months) { month in
                        Text(monthLabel(for: month.date))
                        .font(.system(size: 8.5, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text3)
                            .fixedSize()
                            .offset(x: leadingWidth + CGFloat(month.column) * (cellWidth + gap))
                    }
                }
            }
            .frame(height: 10)
            .padding(.top, 9)
            HStack(alignment: .top, spacing: 7) {
                VStack(spacing: 3) {
                    ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 19, height: 9, alignment: .leading)
                    }
                }
                TokenYearHeatmap(
                    levels: snapshot.levels,
                    values: snapshot.values,
                    labels: snapshot.labels,
                    leadingOffset: snapshot.leadingOffset,
                    language: language.language
                )
                    .frame(height: 81)
            }
            .padding(.top, 2)
        }
    }

    private var weekdayLabels: [String] {
        language.language == .simplifiedChinese
            ? ["一", "", "三", "", "五", "", "日"]
            : ["M", "", "W", "", "F", "", "S"]
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private var yearHeatmapSnapshot: YearHeatmapSnapshot {
        let rows = DailyTokenUsage.filledHistory(from: store.totalTokenHistory, endingAt: .now, dayCount: 365)
        let peak = max(rows.map(\.total).max() ?? 1, 1)
        let levels = rows.map { row in
            guard row.total > 0 else { return 0 }
            let ratio = Double(row.total) / Double(peak)
            if ratio > 0.75 { return 4 }
            if ratio > 0.5 { return 3 }
            if ratio > 0.25 { return 2 }
            return 1
        }
        guard let first = rows.first?.day, let last = rows.last?.day else {
            return YearHeatmapSnapshot(levels: levels, values: rows.map(\.total), labels: [], leadingOffset: 0, months: [])
        }

        let layout = CalendarHeatmapLayout(start: first, end: last)
        return YearHeatmapSnapshot(
            levels: levels,
            values: rows.map(\.total),
            labels: rows.map { heatmapDayLabel(for: $0.day) },
            leadingOffset: layout.leadingOffset,
            months: layout.months
        )
    }

    private func heatmapDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateFormat = language.language == .simplifiedChinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    private var tokenDashboard: TokenDashboardSnapshot {
        let presentation = store.tokenDashboardSnapshot(for: tokenPeriod.presentationPeriod)
        return TokenDashboardSnapshot(
            total: presentation.summary.total,
            average: presentation.summary.average,
            peak: presentation.summary.peak,
            platform: presentation.platform.map(platformBreakdownItem),
            models: presentation.models.map { row in
                ModelRow(
                    model: row.key.displayName(other: language.text("tokens.otherModel")),
                    total: row.total,
                    share: row.share
                )
            }
        )
    }

    private func chartAxisIndices(for rows: [TokenChartRow]) -> [Int] {
        guard !rows.isEmpty else { return [] }
        guard rows.count > 7 else { return Array(rows.indices) }
        let last = rows.count - 1
        return [0, last / 4, last / 2, last * 3 / 4, last]
    }

    private var tokenChartDimensionPicker: some View {
        PanelSegmentedControl(
            options: TokenChartDimension.allCases,
            selection: $tokenChartDimension
        ) { dimension in
            language.text(dimension.localizationKey)
        }
    }

    var hourlyChartAxisIndices: [Int] {
        [0, 4, 8, 12, 16, 20]
    }

    func hourlyTokenChartSnapshot() -> TokenChartSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let buckets = store.tokenBuckets.filter {
            calendar.isDate($0.bucketStart, inSameDayAs: today) && $0.total > 0
        }
        var valuesByHour: [Int: Int] = [:]
        for bucket in buckets {
            let hour = calendar.component(.hour, from: bucket.bucketStart)
            valuesByHour[hour, default: 0] += bucket.total
        }
        let rows = (0..<24).map { hour in
            let value = valuesByHour[hour] ?? 0
            let segments = value > 0
                ? [TokenChartSegment(
                    id: "hourly-total",
                    name: language.text("panel.totalTokens"),
                    value: value,
                    color: PanelTheme.chartPrimary
                )]
                : []
            return TokenChartRow(
                id: "hour-\(hour)",
                label: String(format: "%02d:00-%02d:00", hour, (hour + 1) % 24),
                isToday: false,
                segments: segments
            )
        }
        return TokenChartSnapshot(rows: rows, legend: [])
    }

    private func tokenChartSnapshot() -> TokenChartSnapshot {
        let chartStart = tokenChartStartDate
        let dayCount = tokenChartDayCount(startingAt: chartStart)
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        let filteredBuckets = store.tokenBuckets.filter { bucket in
            let day = calendar.startOfDay(for: bucket.bucketStart)
            return day >= chartStart && day <= end && bucket.total > 0
        }

        let categories = Dictionary(
            filteredBuckets.map { chartCategory(for: $0) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let totalsByCategory = filteredBuckets.reduce(into: [String: Int]()) { totals, bucket in
            let category = chartCategory(for: bucket)
            totals[category.id, default: 0] += bucket.total
        }
        let sortedCategoryIDs = totalsByCategory.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map(\.key)
        // The trend chart is the detailed view: show every platform and model
        // category. The compact four-plus-other grouping belongs to the lists
        // below the chart, not to this chart or its legend.
        let chartCategoryIDs = Set(sortedCategoryIDs)
        let visibleCategories = categories.values.filter { chartCategoryIDs.contains($0.id) }
        let categoryColors = categoryColors(for: Array(visibleCategories))

        var valuesByDay: [String: [String: Int]] = [:]
        for bucket in filteredBuckets {
            let category = chartCategory(for: bucket)
            let dayKey = DailyTokenUsage.dayKey(for: calendar.startOfDay(for: bucket.bucketStart))
            valuesByDay[dayKey, default: [:]][category.id, default: 0] += bucket.total
        }

        let rows: [TokenChartRow] = (0..<dayCount).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index - (dayCount - 1), to: end) else { return nil }
            let dayKey = DailyTokenUsage.dayKey(for: day)
            let values = valuesByDay[dayKey] ?? [:]
            let segments = values.compactMap { id, value -> TokenChartSegment? in
                guard value > 0 else { return nil }
                guard let category = categories[id] else { return nil }
                return TokenChartSegment(
                    id: category.id,
                    name: category.name,
                    value: value,
                    color: categoryColors[category.id] ?? PanelTheme.modelFallback
                )
            }
            .sorted { $0.id < $1.id }
            return TokenChartRow(
                id: dayKey,
                label: chartLabel(for: day),
                isToday: dayKey == DailyTokenUsage.dayKey(for: .now),
                segments: segments
            )
        }

        let displayedTotals = rows.flatMap(\.segments).reduce(into: [String: Int]()) { totals, segment in
            totals[segment.id, default: 0] += segment.value
        }
        let legendCategories = rows.flatMap(\.segments)
            .reduce(into: [String: TokenChartLegendItem]()) { result, segment in
                result[segment.id] = TokenChartLegendItem(id: segment.id, name: segment.name, color: segment.color)
            }
            .values
            .sorted { lhs, rhs in
                let left = displayedTotals[lhs.id] ?? totalsByCategory[lhs.id] ?? 0
                let right = displayedTotals[rhs.id] ?? totalsByCategory[rhs.id] ?? 0
                if left != right { return left > right }
                return lhs.id < rhs.id
            }

        return TokenChartSnapshot(rows: rows, legend: legendCategories)
    }

    private var tokenChartStartDate: Date {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        if let fixedDayCount = tokenPeriod.fixedDayCount {
            return calendar.date(byAdding: .day, value: -(fixedDayCount - 1), to: end) ?? end
        }
        let earliest = (store.tokenBuckets.map(\.bucketStart) + store.totalTokenHistory.map(\.day)).min()
        return earliest.map(calendar.startOfDay) ?? end
    }

    private func tokenChartDayCount(startingAt start: Date) -> Int {
        let end = Calendar.current.startOfDay(for: .now)
        return max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0, 0) + 1
    }

    private func chartLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateFormat = tokenPeriod == .all ? "MM-dd" : "MM-dd"
        return formatter.string(from: date)
    }

    func categoryColors(for categories: [TokenChartCategory]) -> [String: Color] {
        let palette = PanelTheme.categoryPalette
        return Dictionary(
            categories.map { category in
                (category.id, palette[category.preferredPaletteIndex % palette.count])
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func chartCategory(for bucket: TokenUsageBucket) -> TokenChartCategory {
        chartCategory(for: bucket, dimension: tokenChartDimension)
    }

    private func chartCategory(for bucket: TokenUsageBucket, dimension: TokenChartDimension) -> TokenChartCategory {
        switch dimension {
        case .platform:
            let key = UsageBreakdownKey.platformClient(platform: bucket.platform, client: bucket.client)
            return TokenChartCategory(
                id: key.stableID,
                name: key.displayName(claudeCode: language.text("panel.claudeCode")),
                preferredPaletteIndex: UsageBreakdownColor.categoryIndex(for: key)
            )
        case .model:
            let model = TokenModelName.canonical(bucket.model)
            return TokenChartCategory(
                id: "model|\(model)",
                name: model,
                preferredPaletteIndex: UsageBreakdownColor.stableIndex(for: model)
            )
        }
    }

    struct BreakdownItem: Identifiable {
        let name: String
        let value: Int
        let share: Double
        let color: Color

        var id: String { name }
    }

    struct TokenChartCategory {
        let id: String
        let name: String
        let preferredPaletteIndex: Int
    }

    struct TokenChartSegment: Identifiable {
        let id: String
        let name: String
        let value: Int
        let color: Color
    }

    struct TokenChartRow: Identifiable {
        let id: String
        let label: String
        let isToday: Bool
        let segments: [TokenChartSegment]

        var total: Int { segments.reduce(0) { $0 + $1.value } }
    }

    struct TokenChartLegendItem: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    struct TokenChartSnapshot {
        let rows: [TokenChartRow]
        let legend: [TokenChartLegendItem]
    }

    private struct TokenDashboardSnapshot {
        let total: Int
        let average: Int
        let peak: Int
        let platform: [BreakdownItem]
        let models: [ModelRow]
    }

    private struct YearHeatmapSnapshot {
        let levels: [Int]
        let values: [Int]
        let labels: [String]
        let leadingOffset: Int
        let months: [CalendarHeatmapLayout.MonthMarker]
    }

    private var tokenPeriodPicker: some View {
        PanelSegmentedControl(
            options: TokenPeriod.allCases,
            selection: $tokenPeriod,
            isEnabled: tokenPeriodIsAvailable,
            disabledHelp: { _ in language.text("panel.insufficientHistory") }
        ) { period in
            language.text(period.localizationKey)
        }
    }

    private func tokenPeriodIsAvailable(_ period: TokenPeriod) -> Bool {
        let history = store.presentationSnapshot.history
        return switch period {
        case .sevenDays: history.supportsSevenDays
        case .thirtyDays: history.supportsThirtyDays
        case .ninetyDays: history.supportsNinetyDays
        case .all: history.recordedDayCount > 0
        }
    }

    private func selectAvailableTokenPeriodIfNeeded() {
        guard !tokenPeriodIsAvailable(tokenPeriod) else { return }
        if tokenPeriodIsAvailable(.all) {
            tokenPeriod = .all
        }
    }


}
