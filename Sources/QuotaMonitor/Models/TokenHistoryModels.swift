import Foundation

/// 按天聚合的 Codex token 用量（来自本地会话日志）。
/// `day` 已归一化到本地零点，`id` 为该天的稳定 key，便于与历史数组比对。
struct DailyTokenUsage: Identifiable, Codable, Equatable, Sendable {
    let day: Date
    let input: Int
    let cachedInput: Int
    let cacheWriteInput: Int
    let output: Int
    let reasoning: Int

    /// 消耗口径与 Codex 会话文件里的 total_tokens 一致：input + output。
    /// input_tokens 已包含缓存命中部分，reasoning 单独列示、不计入总数。
    var total: Int { input + output }

    var id: String { Self.dayKey(for: day) }

    init(day: Date, input: Int, cachedInput: Int, cacheWriteInput: Int, output: Int, reasoning: Int) {
        self.day = day
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWriteInput = cacheWriteInput
        self.output = output
        self.reasoning = reasoning
    }

    init(day: Date, totals: TokenTotals) {
        self.init(
            day: day,
            input: totals.input,
            cachedInput: totals.cachedInput,
            cacheWriteInput: totals.cacheWriteInput,
            output: totals.output,
            reasoning: totals.reasoning
        )
    }

    /// 跨同一天多个会话文件时，把各自的累计值相加。
    func adding(_ other: DailyTokenUsage) -> DailyTokenUsage {
        DailyTokenUsage(
            day: day,
            input: input + other.input,
            cachedInput: cachedInput + other.cachedInput,
            cacheWriteInput: cacheWriteInput + other.cacheWriteInput,
            output: output + other.output,
            reasoning: reasoning + other.reasoning
        )
    }

    /// 今日与昨日的相对变化百分比；昨日为 0 或缺失时返回 nil。
    static func trendPercent(today: Int, yesterday: Int) -> Double? {
        guard yesterday > 0 else { return nil }
        return (Double(today) - Double(yesterday)) / Double(yesterday) * 100
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    /// 返回连续的最近几天；没有会话记录的日期用全 0 条目补齐。
    ///
    /// 图表需要按自然日展示数据，不能直接对稀疏的会话聚合结果取 suffix，
    /// 否则中间没有使用的日期会被跳过。
    static func filledHistory(
        from history: [DailyTokenUsage],
        endingAt endDate: Date = .now,
        dayCount: Int = 7,
        calendar: Calendar = .current
    ) -> [DailyTokenUsage] {
        guard dayCount > 0 else { return [] }

        let endDay = calendar.startOfDay(for: endDate)
        var usageByDay: [String: DailyTokenUsage] = [:]
        for usage in history {
            let normalizedDay = calendar.startOfDay(for: usage.day)
            let normalized = DailyTokenUsage(
                day: normalizedDay,
                input: usage.input,
                cachedInput: usage.cachedInput,
                cacheWriteInput: usage.cacheWriteInput,
                output: usage.output,
                reasoning: usage.reasoning
            )
            let key = dayKey(for: normalizedDay, calendar: calendar)
            if let existing = usageByDay[key] {
                usageByDay[key] = existing.adding(normalized)
            } else {
                usageByDay[key] = normalized
            }
        }

        return (0..<dayCount).compactMap { index in
            guard let day = calendar.date(
                byAdding: .day,
                value: index - (dayCount - 1),
                to: endDay
            ) else { return nil }

            let key = dayKey(for: day, calendar: calendar)
            return usageByDay[key] ?? DailyTokenUsage(day: day, totals: TokenTotals())
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return dayKey(for: date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// 单文件解析出的 token 累计值（会话内为累计量，取末值即可）。
struct TokenTotals: Codable, Equatable, Sendable {
    var input: Int = 0
    var cachedInput: Int = 0
    var cacheWriteInput: Int = 0
    var output: Int = 0
    var reasoning: Int = 0
}

extension TokenTotals {
    /// 跨来源聚合时把两个累计量相加。
    func adding(_ other: TokenTotals) -> TokenTotals {
        var copy = self
        copy.input += other.input
        copy.cachedInput += other.cachedInput
        copy.cacheWriteInput += other.cacheWriteInput
        copy.output += other.output
        copy.reasoning += other.reasoning
        return copy
    }

    /// 相邻两条累计量的差，得到单次请求的增量；负数按 0 处理。
    func subtracting(_ other: TokenTotals) -> TokenTotals {
        var copy = self
        copy.input = max(copy.input - other.input, 0)
        copy.cachedInput = max(copy.cachedInput - other.cachedInput, 0)
        copy.cacheWriteInput = max(copy.cacheWriteInput - other.cacheWriteInput, 0)
        copy.output = max(copy.output - other.output, 0)
        copy.reasoning = max(copy.reasoning - other.reasoning, 0)
        return copy
    }

    /// 是否有任何 token 增量。
    var hasAnyUsage: Bool {
        input + cachedInput + cacheWriteInput + output + reasoning > 0
    }
}
