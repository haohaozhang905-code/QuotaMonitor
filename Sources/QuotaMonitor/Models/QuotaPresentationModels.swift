import Foundation

/// UI 只消费这个层的统计结果；数据源、路由和展示文案不在 View 内重新聚合。
enum QuotaAvailability: Equatable, Sendable {
    case loading
    case ready
    case connectedOnly
    case unavailable
    case stale
    case error
}

/// 可被下拉框、概览页和 Token 看板复用的统计窗口。
struct TokenUsageSummary: Equatable, Sendable {
    let total: Int
    let dayCount: Int
    let average: Int
    let peak: Int
    /// 仅「今日」窗口有值，分母始终是昨日总量。
    let trendPercent: Double?
}

/// 保持工具、客户端和模型三个维度独立；展示层按需要将工具和客户端组合成一行。
enum UsageBreakdownKey: Hashable, Sendable {
    case platformClient(platform: TokenPlatform, client: TokenClient)
    case model(String)
    case otherModels
}

extension UsageBreakdownKey {
    var stableID: String {
        switch self {
        case let .platformClient(platform, client):
            return "platform|\(platform.rawValue)|\(client.rawValue)"
        case let .model(model):
            return "model|\(model)"
        case .otherModels:
            return "model|other"
        }
    }

    func displayName(claudeCode: String = "Claude Code", other: String = "其他") -> String {
        switch self {
        case let .platformClient(platform, client):
            switch (platform, client) {
            case (.codex, _): platform.displayName
            case (.claude, .cli): claudeCode
            case (.claude, _), (.workbuddy, _), (.kimi, _): platform.displayName
            }
        case let .model(model): model
        case .otherModels: other
        }
    }
}

struct UsageBreakdownSnapshot: Identifiable, Equatable, Sendable {
    let key: UsageBreakdownKey
    let total: Int
    let share: Double

    var id: String { key.stableID }
}

struct HistoryAvailability: Equatable, Sendable {
    let earliestDate: Date?
    let recordedDayCount: Int
    let supportsSevenDays: Bool
    let supportsThirtyDays: Bool
    let supportsNinetyDays: Bool
    let supportsYear: Bool
}

/// Token 看板的时间范围与页面内部的按钮一一对应。
enum TokenDashboardPeriod: Equatable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case all

    var fixedDayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .all: nil
        }
    }
}

struct TokenDashboardPresentation: Equatable, Sendable {
    let period: TokenDashboardPeriod
    let summary: TokenUsageSummary
    let platform: [UsageBreakdownSnapshot]
    let models: [UsageBreakdownSnapshot]
}

/// 下拉框中的单个官方额度指标。保留数值和日期，交由界面层按当前语言格式化。
struct DropdownQuotaMetricPresentation: Equatable, Sendable {
    let remainingPercent: Double?
    let resetsAt: Date?
}

/// 额度的连接状态与读取状态独立表达，避免用 `--` 掩盖真实原因。
enum DropdownQuotaState: Equatable, Sendable {
    case official(
        plan: String?,
        session: DropdownQuotaMetricPresentation?,
        weekly: DropdownQuotaMetricPresentation?
    )
    case sharedBalance(amount: Double, currency: String?, estimatedDays: Int?)
    case connectedWithoutQuota
    case unavailable
}

/// 下拉框只展示已经检测到路由的额度来源；未安装或未配置的平台不创建条目。
struct DropdownQuotaPresentation: Identifiable, Equatable, Sendable {
    let platform: TokenPlatform
    let state: DropdownQuotaState

    var id: String { platform.rawValue }
}

/// 下拉框使用的专用快照。它不包含任何视图或本地化文案。
struct DropdownPresentation: Equatable, Sendable {
    let availability: QuotaAvailability
    let updatedAt: Date?
    let today: TokenUsageSummary
    let platformToday: [UsageBreakdownSnapshot]
    let topModels: [UsageBreakdownSnapshot]
    let quotaItems: [DropdownQuotaPresentation]
}

/// 跨页面共享的只读展示快照。它只保存原始数值和状态，文案格式化仍由 UI 层根据语言完成。
struct QuotaPresentationSnapshot: Equatable, Sendable {
    let availability: QuotaAvailability
    let updatedAt: Date?
    let today: TokenUsageSummary
    let lastSevenDays: TokenUsageSummary
    let platformToday: [UsageBreakdownSnapshot]
    let platformLastSevenDays: [UsageBreakdownSnapshot]
    let modelToday: [UsageBreakdownSnapshot]
    let modelLastSevenDays: [UsageBreakdownSnapshot]
    let history: HistoryAvailability

    /// 下拉框展示今日 Top N 模型并合并其余项，确保平台与模型使用同一个“今日”时间窗口。
    func topModels(limit: Int = 3) -> [UsageBreakdownSnapshot] {
        guard limit >= 0, modelToday.count > limit else { return modelToday }
        let top = Array(modelToday.prefix(limit))
        let otherTotal = modelToday.dropFirst(limit).reduce(0) { $0 + $1.total }
        guard otherTotal > 0 else { return top }
        let total = modelToday.reduce(0) { $0 + $1.total }
        return top + [UsageBreakdownSnapshot(
            key: .otherModels,
            total: otherTotal,
            share: total > 0 ? Double(otherTotal) / Double(total) : 0
        )]
    }

    static func make(
        providers: [ProviderUsage],
        updatedAt: Date?,
        errorMessageKey: String?,
        isRefreshing: Bool,
        codexRoute: CodexRoute,
        claudeRoute: ClaudeRoute,
        totalHistory: [DailyTokenUsage],
        buckets: [TokenUsageBucket],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Self {
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let dailyTotals = totalsByDay(totalHistory, calendar: calendar)
        let todayTotal = dailyTotals[DailyTokenUsage.dayKey(for: todayStart)] ?? 0
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let yesterdayTotal = dailyTotals[DailyTokenUsage.dayKey(for: yesterday)]
        let sevenDayValues = (0..<7).compactMap { offset -> Int? in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: todayStart) else { return nil }
            return dailyTotals[DailyTokenUsage.dayKey(for: day)] ?? 0
        }

        let hasUsage = totalHistory.contains { $0.total > 0 }
        let hasConnection = codexRoute != .unknown || claudeRoute != .unknown
        return Self(
            availability: availability(
                hasUsage: hasUsage,
                hasQuotaData: !providers.isEmpty,
                hasConnection: hasConnection,
                updatedAt: updatedAt,
                errorMessageKey: errorMessageKey,
                isRefreshing: isRefreshing,
                now: now
            ),
            updatedAt: updatedAt,
            today: TokenUsageSummary(
                total: todayTotal,
                dayCount: 1,
                average: todayTotal,
                peak: todayTotal,
                trendPercent: yesterdayTotal.flatMap { DailyTokenUsage.trendPercent(today: todayTotal, yesterday: $0) }
            ),
            lastSevenDays: summary(values: sevenDayValues),
            platformToday: breakdown(
                buckets: buckets,
                startingAt: todayStart,
                key: { .platformClient(platform: $0.platform, client: $0.client) }
            ),
            platformLastSevenDays: breakdown(
                buckets: buckets,
                startingAt: sevenDayStart,
                key: { .platformClient(platform: $0.platform, client: $0.client) }
            ),
            modelToday: breakdown(
                buckets: buckets,
                startingAt: todayStart,
                key: { .model($0.model) }
            ),
            modelLastSevenDays: breakdown(
                buckets: buckets,
                startingAt: sevenDayStart,
                key: { .model($0.model) }
            ),
            history: historyAvailability(history: totalHistory, now: now, calendar: calendar)
        )
    }

    static func makeTokenDashboard(
        period: TokenDashboardPeriod,
        totalHistory: [DailyTokenUsage],
        buckets: [TokenUsageBucket],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TokenDashboardPresentation {
        let end = calendar.startOfDay(for: now)
        let earliestDataDate = (totalHistory.map(\.day) + buckets.map(\.bucketStart)).min()
            .map { calendar.startOfDay(for: $0) }
        let dayCount: Int
        let start: Date
        if let fixedDayCount = period.fixedDayCount {
            dayCount = fixedDayCount
            start = calendar.date(byAdding: .day, value: -(fixedDayCount - 1), to: end) ?? end
        } else if let earliestDataDate {
            start = earliestDataDate
            dayCount = max((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
        } else {
            start = end
            dayCount = 1
        }

        let dailyValues = DailyTokenUsage.filledHistory(
            from: totalHistory,
            endingAt: end,
            dayCount: dayCount,
            calendar: calendar
        ).map(\.total)
        return TokenDashboardPresentation(
            period: period,
            summary: summary(values: dailyValues),
            platform: breakdown(
                buckets: buckets,
                startingAt: start,
                key: { .platformClient(platform: $0.platform, client: $0.client) }
            ),
            models: breakdown(
                buckets: buckets,
                startingAt: start,
                key: { .model($0.model) }
            )
        )
    }

    static func makeDropdown(
        presentation: Self,
        providers: [ProviderUsage],
        codexRoute: CodexRoute,
        claudeRoute: ClaudeRoute,
        deepSeekBalance: Double?,
        deepSeekCurrency: String?,
        deepSeekDays: Int?
    ) -> DropdownPresentation {
        let codex = providers.first { $0.providerId.lowercased() == "codex" }
        var quotaItems: [DropdownQuotaPresentation] = []
        if codexRoute != .unknown {
            quotaItems.append(.init(
                platform: .codex,
                state: quotaState(
                    route: codexRoute,
                    provider: codex,
                    deepSeekBalance: deepSeekBalance,
                    deepSeekCurrency: deepSeekCurrency,
                    deepSeekDays: deepSeekDays
                )
            ))
        }
        if claudeRoute != .unknown {
            quotaItems.append(.init(
                platform: .claude,
                state: quotaState(
                    route: claudeRoute,
                    provider: nil,
                    deepSeekBalance: deepSeekBalance,
                    deepSeekCurrency: deepSeekCurrency,
                    deepSeekDays: deepSeekDays
                )
            ))
        }
        return DropdownPresentation(
            availability: presentation.availability,
            updatedAt: presentation.updatedAt,
            today: presentation.today,
            platformToday: presentation.platformToday,
            topModels: presentation.topModels(),
            quotaItems: quotaItems
        )
    }

    private static func availability(
        hasUsage: Bool,
        hasQuotaData: Bool,
        hasConnection: Bool,
        updatedAt: Date?,
        errorMessageKey: String?,
        isRefreshing: Bool,
        now: Date
    ) -> QuotaAvailability {
        if errorMessageKey != nil, !hasUsage, !hasQuotaData { return .error }
        if isRefreshing, !hasUsage, !hasQuotaData { return .loading }
        if errorMessageKey != nil, hasUsage || hasQuotaData { return .stale }
        if let updatedAt, now.timeIntervalSince(updatedAt) > 5 * 60 { return .stale }
        if hasUsage || hasQuotaData { return .ready }
        if hasConnection { return .connectedOnly }
        return .unavailable
    }

    private static func quotaState(
        route: CodexRoute,
        provider: ProviderUsage?,
        deepSeekBalance: Double?,
        deepSeekCurrency: String?,
        deepSeekDays: Int?
    ) -> DropdownQuotaState {
        switch route {
        case .deepseek:
            guard let deepSeekBalance else { return .connectedWithoutQuota }
            return .sharedBalance(
                amount: deepSeekBalance,
                currency: deepSeekCurrency,
                estimatedDays: deepSeekDays
            )
        case .official:
            let session = provider?.session.map(metricPresentation)
            let weekly = provider?.weekly.map(metricPresentation)
            guard session != nil || weekly != nil else { return .connectedWithoutQuota }
            return .official(plan: provider?.plan, session: session, weekly: weekly)
        case .unknown:
            return .unavailable
        }
    }

    private static func quotaState(
        route: ClaudeRoute,
        provider: ProviderUsage?,
        deepSeekBalance: Double?,
        deepSeekCurrency: String?,
        deepSeekDays: Int?
    ) -> DropdownQuotaState {
        switch route {
        case .deepseek:
            guard let deepSeekBalance else { return .connectedWithoutQuota }
            return .sharedBalance(
                amount: deepSeekBalance,
                currency: deepSeekCurrency,
                estimatedDays: deepSeekDays
            )
        case .official:
            let session = provider?.session.map(metricPresentation)
            let weekly = provider?.weekly.map(metricPresentation)
            guard session != nil || weekly != nil else { return .connectedWithoutQuota }
            return .official(plan: provider?.plan, session: session, weekly: weekly)
        case .unknown:
            return .unavailable
        }
    }

    private static func metricPresentation(_ line: UsageLine) -> DropdownQuotaMetricPresentation {
        DropdownQuotaMetricPresentation(
            remainingPercent: line.remainingPercent,
            resetsAt: line.resetsAt
        )
    }

    private static func summary(values: [Int]) -> TokenUsageSummary {
        let total = values.reduce(0, +)
        return TokenUsageSummary(
            total: total,
            dayCount: values.count,
            average: values.isEmpty ? 0 : total / values.count,
            peak: values.max() ?? 0,
            trendPercent: nil
        )
    }

    private static func breakdown(
        buckets: [TokenUsageBucket],
        startingAt start: Date,
        key: (TokenUsageBucket) -> UsageBreakdownKey
    ) -> [UsageBreakdownSnapshot] {
        var totals: [UsageBreakdownKey: Int] = [:]
        for bucket in buckets where bucket.bucketStart >= start {
            totals[key(bucket), default: 0] += bucket.total
        }
        let total = totals.values.reduce(0, +)
        return totals
            .map { UsageBreakdownSnapshot(key: $0.key, total: $0.value, share: total > 0 ? Double($0.value) / Double(total) : 0) }
            .sorted {
                if $0.total != $1.total { return $0.total > $1.total }
                return $0.id < $1.id
            }
    }

    private static func totalsByDay(_ history: [DailyTokenUsage], calendar: Calendar) -> [String: Int] {
        history.reduce(into: [:]) { totals, usage in
            let key = DailyTokenUsage.dayKey(for: calendar.startOfDay(for: usage.day))
            totals[key, default: 0] += usage.total
        }
    }

    private static func historyAvailability(
        history: [DailyTokenUsage],
        now: Date,
        calendar: Calendar
    ) -> HistoryAvailability {
        let days = Set(history.map { DailyTokenUsage.dayKey(for: calendar.startOfDay(for: $0.day)) })
        let earliest = history.map(\.day).min().map { calendar.startOfDay(for: $0) }
        func supports(_ dayCount: Int) -> Bool {
            guard let earliest,
                  let requiredStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: calendar.startOfDay(for: now)) else {
                return false
            }
            return earliest <= requiredStart
        }
        return HistoryAvailability(
            earliestDate: earliest,
            recordedDayCount: days.count,
            supportsSevenDays: supports(7),
            supportsThirtyDays: supports(30),
            supportsNinetyDays: supports(90),
            supportsYear: supports(365)
        )
    }
}
