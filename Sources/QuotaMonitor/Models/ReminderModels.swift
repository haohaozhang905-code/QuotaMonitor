import Foundation

enum ReminderQuotaMetric: String, Codable, Sendable {
    case session
    case weekly
}

enum ReminderDestination: String, Codable, Sendable {
    case overview
    case tokens
}

enum ReminderEvent: Equatable, Sendable {
    case codexQuota(metric: ReminderQuotaMetric, remainingPercent: Int, resetsAt: Date?)
    case deepSeekBalance(amount: Double, currency: String)
    case dailyTokens(total: Int, milestone: Int)

    var destination: ReminderDestination {
        switch self {
        case .dailyTokens: .tokens
        case .codexQuota, .deepSeekBalance: .overview
        }
    }
}

struct ReminderRuleInput: Equatable, Sendable {
    let now: Date
    let dayKey: String
    let codexSessionRemaining: Double?
    let codexSessionResetAt: Date?
    let codexWeeklyRemaining: Double?
    let codexWeeklyResetAt: Date?
    let deepSeekRouteIsActive: Bool
    let deepSeekBalance: Double?
    let deepSeekCurrency: String?
    let todayTokenTotal: Int?
}

struct ReminderRuleLedger: Codable, Equatable, Sendable {
    var firedQuotaEventIDs: Set<String> = []
    var lowQuotaMetricsWithoutWindow: Set<ReminderQuotaMetric> = []
    var deepSeekLowBalanceActive = false
    var tokenDayKey: String?
    var highestTokenMilestone = 0
}

enum ReminderRuleEvaluator {
    static let quotaThresholdPercent = 30
    static let deepSeekThresholdCNY = 5.0
    static let deepSeekRearmCNY = 6.0
    static let tokenMilestoneSize = 100_000_000

    static func evaluate(
        input: ReminderRuleInput,
        ledger: inout ReminderRuleLedger
    ) -> [ReminderEvent] {
        var events: [ReminderEvent] = []

        evaluateQuota(
            metric: .session,
            remaining: input.codexSessionRemaining,
            resetsAt: input.codexSessionResetAt,
            dayKey: input.dayKey,
            ledger: &ledger
        ).map { events.append($0) }
        evaluateQuota(
            metric: .weekly,
            remaining: input.codexWeeklyRemaining,
            resetsAt: input.codexWeeklyResetAt,
            dayKey: input.dayKey,
            ledger: &ledger
        ).map { events.append($0) }

        evaluateDeepSeek(input: input, ledger: &ledger).map { events.append($0) }
        evaluateTokens(input: input, ledger: &ledger).map { events.append($0) }
        return events
    }

    private static func evaluateQuota(
        metric: ReminderQuotaMetric,
        remaining: Double?,
        resetsAt: Date?,
        dayKey: String,
        ledger: inout ReminderRuleLedger
    ) -> ReminderEvent? {
        guard let remaining else { return nil }
        // 与界面百分比保持同一取整方式：用户看到 30% 时，提醒也应命中。
        let displayedPercent = Int((min(max(remaining, 0), 1) * 100).rounded())
        guard displayedPercent <= quotaThresholdPercent else {
            if resetsAt == nil { ledger.lowQuotaMetricsWithoutWindow.remove(metric) }
            return nil
        }

        if let resetsAt {
            let eventID = "codex.\(metric.rawValue).\(Int(resetsAt.timeIntervalSince1970))"
            guard ledger.firedQuotaEventIDs.insert(eventID).inserted else { return nil }
        } else {
            guard ledger.lowQuotaMetricsWithoutWindow.insert(metric).inserted else { return nil }
        }
        return .codexQuota(metric: metric, remainingPercent: displayedPercent, resetsAt: resetsAt)
    }

    private static func evaluateDeepSeek(
        input: ReminderRuleInput,
        ledger: inout ReminderRuleLedger
    ) -> ReminderEvent? {
        guard input.deepSeekRouteIsActive else {
            ledger.deepSeekLowBalanceActive = false
            return nil
        }
        guard let balance = input.deepSeekBalance,
              input.deepSeekCurrency?.uppercased() == "CNY" else { return nil }

        if balance >= deepSeekRearmCNY {
            ledger.deepSeekLowBalanceActive = false
            return nil
        }
        guard balance < deepSeekThresholdCNY, !ledger.deepSeekLowBalanceActive else { return nil }
        ledger.deepSeekLowBalanceActive = true
        return .deepSeekBalance(amount: balance, currency: "CNY")
    }

    private static func evaluateTokens(
        input: ReminderRuleInput,
        ledger: inout ReminderRuleLedger
    ) -> ReminderEvent? {
        if ledger.tokenDayKey != input.dayKey {
            ledger.tokenDayKey = input.dayKey
            ledger.highestTokenMilestone = 0
        }
        guard let total = input.todayTokenTotal, total >= tokenMilestoneSize else { return nil }
        let milestone = total / tokenMilestoneSize
        guard milestone > ledger.highestTokenMilestone else { return nil }
        ledger.highestTokenMilestone = milestone
        // 一次同步跨过多个亿级时只发最高里程碑，并把较低档位一并记为已提醒。
        return .dailyTokens(total: total, milestone: milestone)
    }
}

struct ReminderPresentation: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let details: [String]
    let destination: ReminderDestination

    var body: String { details.joined(separator: "\n") }
}
