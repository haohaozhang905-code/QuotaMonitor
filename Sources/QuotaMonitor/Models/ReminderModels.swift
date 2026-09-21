import Foundation

enum ReminderQuotaMetric: String, Codable, CaseIterable, Sendable {
    case session
    case weekly
}

enum ReminderQuotaResetKind: String, Codable, Sendable {
    case scheduled
    case early
}

enum ReminderDestination: String, Codable, Sendable {
    case overview
    case tokens
}

struct Observed<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let fetchedAt: Date
    let isFresh: Bool
}

struct ReminderCodexQuotaSnapshot: Equatable, Sendable {
    let sessionRemaining: Double?
    let sessionResetAt: Date?
    let sessionPeriodDuration: TimeInterval?
    let weeklyRemaining: Double?
    let weeklyResetAt: Date?
    let weeklyPeriodDuration: TimeInterval?
    // Raw provider deadlines are evidence for a cycle change. The effective
    // deadlines above may be synthesized for display and must not rearm alerts.
    var sessionRawResetAt: Date? = nil
    var weeklyRawResetAt: Date? = nil
}

struct ReminderResetCreditsInput: Equatable, Sendable {
    let availableCount: Int
    let expirations: [Date]
    let fetchedAt: Date
}

struct ReminderDeepSeekBalance: Equatable, Sendable {
    let amount: Double
    let currency: String
}

struct ReminderContext: Equatable, Sendable {
    let now: Date
    let dayKey: String
    let codexOfficialRouteIsActive: Bool
    let codexQuota: Observed<ReminderCodexQuotaSnapshot>?
    let codexResetCredits: Observed<ReminderResetCreditsInput>?
    let deepSeekRouteIsActive: Bool
    let deepSeekBalance: Observed<ReminderDeepSeekBalance>?
    let todayTokenTotal: Observed<Int>?
}

struct ReminderCodexObservation: Codable, Equatable, Sendable {
    let sessionDisplayedPercent: Int?
    let sessionResetAt: Date?
    let sessionPeriodDuration: TimeInterval?
    let weeklyDisplayedPercent: Int?
    let weeklyResetAt: Date?
    let weeklyPeriodDuration: TimeInterval?
    let resetCreditsAvailableCount: Int?
    let observedAt: Date
}

enum ReminderRuleID {
    static func quota(_ metric: ReminderQuotaMetric) -> String { "codex.\(metric.rawValue).quota" }
    static let sessionReset = "codex.session.reset"
    static let weeklyReset = "codex.weekly.reset"
    static let resetCreditExpiry = "codex.reset-credit.expiry"
    static let deepSeekBalance = "deepseek.low-balance"
    static let dailyTokens = "tokens.daily.milestone"
}

enum ReminderDataSource: String, Codable, Sendable {
    case codexQuota
    case codexResetCredits
    case deepSeekBalance
    case dailyTokenUsage

    func isFresh(in context: ReminderContext) -> Bool {
        switch self {
        case .codexQuota:
            context.codexOfficialRouteIsActive && context.codexQuota?.isFresh == true
        case .codexResetCredits:
            context.codexOfficialRouteIsActive
                && context.codexQuota?.isFresh == true
                && context.codexResetCredits?.isFresh == true
        case .deepSeekBalance:
            context.deepSeekRouteIsActive && context.deepSeekBalance?.isFresh == true
        case .dailyTokenUsage:
            context.todayTokenTotal?.isFresh == true
        }
    }
}

enum ReminderCondition: Equatable, Sendable {
    case quotaThresholds(metric: ReminderQuotaMetric, levels: [Int])
    case quotaWindowChange(metric: ReminderQuotaMetric, tolerance: TimeInterval, requiresDisplayedPercent: Int, suppressUserInitiated: Bool)
    case expiryWindow(leadTime: TimeInterval)
    case balanceHysteresis(triggerBelow: Double, rearmAt: Double, currency: String)
    case periodMilestone(size: Int)
}

enum ReminderDeduplication: String, Codable, Sendable {
    case quotaWindowAndLevel
    case windowOccurrence
    case individualOccurrence
    case activeUntilRecovery
    case periodHighestMilestone
}

struct ReminderMessageKeys: Equatable, Sendable {
    let title: String
    let body: String?
}

struct ReminderMessageTemplate: Equatable, Sendable {
    let defaultKeys: ReminderMessageKeys
    let variants: [String: ReminderMessageKeys]

    func keys(for variant: String? = nil) -> ReminderMessageKeys {
        variant.flatMap { variants[$0] } ?? defaultKeys
    }

}

struct ReminderRuleDefinition: Equatable, Sendable, Identifiable {
    let id: String
    let source: ReminderDataSource
    let condition: ReminderCondition
    let deduplication: ReminderDeduplication
    let order: Int
    let destination: ReminderDestination
    let message: ReminderMessageTemplate
}

enum ReminderRuleCatalog {
    static let definitions: [ReminderRuleDefinition] = [
        .init(
            id: ReminderRuleID.quota(.session), source: .codexQuota,
            condition: .quotaThresholds(
                metric: .session,
                levels: [QuotaRiskPolicy.criticalDisplayedPercent, QuotaRiskPolicy.reminderDisplayedPercent]
            ),
            deduplication: .quotaWindowAndLevel, order: 10, destination: .overview,
            message: .init(
                defaultKeys: .init(title: "reminder.codex.quota.title", body: "reminder.codex.quota.resetAt"),
                variants: [
                    "warning": .init(title: "reminder.codex.quota.warning.title", body: "reminder.codex.quota.resetAt"),
                    "critical": .init(title: "reminder.codex.quota.critical.title", body: "reminder.codex.quota.resetAt")
                ]
            )
        ),
        .init(
            id: ReminderRuleID.quota(.weekly), source: .codexQuota,
            condition: .quotaThresholds(
                metric: .weekly,
                levels: [QuotaRiskPolicy.criticalDisplayedPercent, QuotaRiskPolicy.reminderDisplayedPercent]
            ),
            deduplication: .quotaWindowAndLevel, order: 20, destination: .overview,
            message: .init(
                defaultKeys: .init(title: "reminder.codex.quota.title", body: "reminder.codex.quota.resetAt"),
                variants: [
                    "warning": .init(title: "reminder.codex.quota.warning.title", body: "reminder.codex.quota.resetAt"),
                    "critical": .init(title: "reminder.codex.quota.critical.title", body: "reminder.codex.quota.resetAt")
                ]
            )
        ),
        .init(
            id: ReminderRuleID.sessionReset, source: .codexQuota,
            condition: .quotaWindowChange(metric: .session, tolerance: 120, requiresDisplayedPercent: 100, suppressUserInitiated: true),
            deduplication: .windowOccurrence, order: 30, destination: .overview,
            message: .init(
                defaultKeys: .init(title: "reminder.codex.sessionReset.scheduled.title", body: "reminder.codex.sessionReset.scheduled.detail"),
                variants: ["early": .init(title: "reminder.codex.sessionReset.early.title", body: "reminder.codex.sessionReset.early.detail")]
            )
        ),
        .init(
            id: ReminderRuleID.weeklyReset, source: .codexQuota,
            condition: .quotaWindowChange(metric: .weekly, tolerance: 120, requiresDisplayedPercent: 100, suppressUserInitiated: true),
            deduplication: .windowOccurrence, order: 40, destination: .overview,
            message: .init(
                defaultKeys: .init(title: "reminder.codex.weeklyReset.scheduled.title", body: "reminder.codex.weeklyReset.scheduled.detail"),
                variants: ["early": .init(title: "reminder.codex.weeklyReset.early.title", body: "reminder.codex.weeklyReset.early.detail")]
            )
        ),
        .init(
            id: ReminderRuleID.resetCreditExpiry, source: .codexResetCredits,
            condition: .expiryWindow(leadTime: 24 * 60 * 60),
            deduplication: .individualOccurrence, order: 50, destination: .overview,
            message: .init(defaultKeys: .init(title: "reminder.codex.resetCreditExpiring.title", body: "reminder.codex.resetCreditExpiring.detail"), variants: [:])
        ),
        .init(
            id: ReminderRuleID.deepSeekBalance, source: .deepSeekBalance,
            condition: .balanceHysteresis(triggerBelow: 5, rearmAt: 6, currency: "CNY"),
            deduplication: .activeUntilRecovery, order: 60, destination: .overview,
            message: .init(defaultKeys: .init(title: "reminder.deepseek.title", body: "reminder.deepseek.detail"), variants: [:])
        ),
        .init(
            id: ReminderRuleID.dailyTokens, source: .dailyTokenUsage,
            condition: .periodMilestone(size: 100_000_000),
            deduplication: .periodHighestMilestone, order: 70, destination: .tokens,
            message: .init(defaultKeys: .init(title: "reminder.tokens.title", body: "reminder.tokens.detail"), variants: [:])
        ),
    ]

    static func definition(_ id: String) -> ReminderRuleDefinition {
        guard let definition = definitions.first(where: { $0.id == id }) else {
            preconditionFailure("Missing reminder rule definition: \(id)")
        }
        return definition
    }
}

enum ReminderMessageArgument: Equatable, Sendable {
    case integer(Int)
    case localized(String)
    case date(Date)
    case money(Double, String)
    case tokens(Int)

    @MainActor
    func resolve(language: LanguageSettings) -> CVarArg {
        switch self {
        case let .integer(value): value
        case let .localized(key): language.text(key)
        case let .date(value): QuotaFormatters.reset(value, language: language.language)
        case let .money(value, currency): QuotaFormatters.money(value, currency: currency)
        case let .tokens(value): QuotaFormatters.localizedTokens(value, language: language.language)
        }
    }
}

struct ReminderMessageDescriptor: Equatable, Sendable {
    let titleKey: String
    let titleArguments: [ReminderMessageArgument]
    let bodyKey: String?
    let bodyArguments: [ReminderMessageArgument]
}

enum ReminderTone: String, Equatable, Sendable {
    case neutral
    case warning
    case critical
}

struct ReminderEvent: Equatable, Sendable, Identifiable {
    let ruleID: String
    let occurrenceID: String
    let order: Int
    let destination: ReminderDestination
    let tone: ReminderTone
    let message: ReminderMessageDescriptor

    var id: String { occurrenceID }

    private static func make(
        ruleID: String,
        occurrenceID: String,
        variant: String? = nil,
        titleArguments: [ReminderMessageArgument] = [],
        bodyArguments: [ReminderMessageArgument] = [],
        includesBody: Bool = true,
        tone: ReminderTone = .neutral
    ) -> Self {
        let rule = ReminderRuleCatalog.definition(ruleID)
        let keys = rule.message.keys(for: variant)
        return Self(
            ruleID: ruleID,
            occurrenceID: occurrenceID,
            order: rule.order,
            destination: rule.destination,
            tone: tone,
            message: ReminderMessageDescriptor(
                titleKey: keys.title,
                titleArguments: titleArguments,
                bodyKey: includesBody ? keys.body : nil,
                bodyArguments: bodyArguments
            )
        )
    }

    static func codexQuota(metric: ReminderQuotaMetric, level: Int, remainingPercent: Int, resetsAt: Date?, generation: Int = 0) -> Self {
        let ruleID = ReminderRuleID.quota(metric)
        let metricKey = metric == .session ? "reminder.metric.session" : "reminder.metric.weekly"
        let id = "codex.\(metric.rawValue).\(level).cycle-\(generation)"
        return make(
            ruleID: ruleID,
            occurrenceID: id,
            variant: level <= QuotaRiskPolicy.criticalDisplayedPercent ? "critical" : "warning",
            titleArguments: [.localized(metricKey), .integer(remainingPercent)],
            bodyArguments: resetsAt.map { [.date($0)] } ?? [],
            includesBody: resetsAt != nil,
            tone: level <= QuotaRiskPolicy.criticalDisplayedPercent ? .critical : .warning
        )
    }

    static func codexQuotaReset(
        metric: ReminderQuotaMetric,
        kind: ReminderQuotaResetKind,
        previousResetAt: Date,
        nextResetAt: Date
    ) -> Self {
        let ruleID = metric == .session ? ReminderRuleID.sessionReset : ReminderRuleID.weeklyReset
        let date = kind == .early ? previousResetAt : nextResetAt
        return make(
            ruleID: ruleID,
            // The server may keep adjusting the next reset time while the displayed
            // allowance remains at 100%. The completed/replaced window is the stable
            // identity of a reset occurrence; the next deadline is presentation data.
            occurrenceID: "codex.\(metric.rawValue)-reset.\(Int(previousResetAt.timeIntervalSince1970))",
            variant: kind.rawValue,
            bodyArguments: [.date(date)]
        )
    }

    static func codexResetCreditExpiring(expiresAt: Date, occurrence: Int) -> Self {
        make(
            ruleID: ReminderRuleID.resetCreditExpiry,
            occurrenceID: "codex.reset-credit-expiry.\(Int(expiresAt.timeIntervalSince1970)).\(occurrence)",
            bodyArguments: [.date(expiresAt)]
        )
    }

    static func deepSeekBalance(amount: Double, currency: String, activationID: String) -> Self {
        make(
            ruleID: ReminderRuleID.deepSeekBalance,
            occurrenceID: "deepseek.low-balance.\(activationID)",
            bodyArguments: [.money(amount, currency)]
        )
    }

    static func dailyTokens(total: Int, milestone: Int, dayKey: String) -> Self {
        make(
            ruleID: ReminderRuleID.dailyTokens,
            occurrenceID: "tokens.daily.\(dayKey).\(milestone)",
            bodyArguments: [.tokens(total)]
        )
    }
}

struct ReminderPresentation: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let details: [String]
    let destination: ReminderDestination
    let tone: ReminderTone

    var body: String { details.joined(separator: "\n") }
}

struct ReminderRuleState: Codable, Equatable, Sendable {
    var firedOccurrenceIDs: Set<String> = []
    var quotaLevelsWithoutWindow: Set<Int> = []
    var active = false
    var highestMilestone = 0
    var periodKey: String?
    var previousCodexObservation: ReminderCodexObservation?
    /// V4: a reset reminder is armed only after this metric has been observed
    /// below the displayed 100% level. Optional keeps V3 ledgers decodable.
    var resetNotificationArmed: Bool? = nil
    // Optional fields keep V1-V4 JSON decodable before V5 migration.
    var quotaGeneration: Int? = nil
    var quotaLevelsFired: Set<Int>? = nil
    var previousQuotaPercent: Int? = nil
    var previousQuotaRawResetAt: Date? = nil

    mutating func record(_ occurrenceID: String, using strategy: ReminderDeduplication) -> Bool {
        if strategy == .activeUntilRecovery {
            guard !active else { return false }
            active = true
            return true
        }
        return firedOccurrenceIDs.insert(occurrenceID).inserted
    }

    func containsQuotaOccurrence(
        metric: ReminderQuotaMetric,
        level: Int,
        resetAt: Date,
        tolerance: TimeInterval
    ) -> Bool {
        let prefix = "codex.\(metric.rawValue).\(level)."
        let target = resetAt.timeIntervalSince1970
        return firedOccurrenceIDs.contains { occurrenceID in
            guard occurrenceID.hasPrefix(prefix),
                  let timestamp = TimeInterval(occurrenceID.dropFirst(prefix.count)) else { return false }
            return abs(timestamp - target) <= tolerance
        }
    }
}

struct ReminderRuleLedger: Codable, Equatable, Sendable {
    var states: [String: ReminderRuleState] = [:]

    init() {}

    mutating func prepareForV4ResetSemantics() {
        for metric in ReminderQuotaMetric.allCases {
            let ruleID = metric == .session ? ReminderRuleID.sessionReset : ReminderRuleID.weeklyReset
            var state = self[ruleID]
            guard state.resetNotificationArmed == nil else { continue }
            let percent = metric == .session
                ? state.previousCodexObservation?.sessionDisplayedPercent
                : state.previousCodexObservation?.weeklyDisplayedPercent
            state.resetNotificationArmed = percent.map { $0 < 100 } ?? false
            self[ruleID] = state
        }
    }

    mutating func prepareForV5QuotaSemantics() {
        for metric in ReminderQuotaMetric.allCases {
            let ruleID = ReminderRuleID.quota(metric)
            var state = self[ruleID]
            guard state.quotaGeneration == nil else { continue }
            let resetState = self[metric == .session ? ReminderRuleID.sessionReset : ReminderRuleID.weeklyReset]
            let previous = resetState.previousCodexObservation
            state.quotaGeneration = 0
            state.previousQuotaPercent = metric == .session ? previous?.sessionDisplayedPercent : previous?.weeklyDisplayedPercent
            state.previousQuotaRawResetAt = metric == .session ? previous?.sessionResetAt : previous?.weeklyResetAt
            let prefix = "codex.\(metric.rawValue)."
            var fired: Set<Int> = []
            for level in [5, 30] where state.firedOccurrenceIDs.contains(where: { $0.hasPrefix("\(prefix)\(level).") }) {
                fired.insert(level)
            }
            fired.formUnion(state.quotaLevelsWithoutWindow)
            if state.previousQuotaPercent == 100 { fired.removeAll() }
            if fired.contains(5) { fired.insert(30) }
            state.quotaLevelsFired = fired
            self[ruleID] = state
        }
    }

    subscript(ruleID: String) -> ReminderRuleState {
        get { states[ruleID] ?? ReminderRuleState() }
        set { states[ruleID] = newValue }
    }

    init(migrating v2: ReminderRuleLedgerV2) {
        self.init()
        for metric in ReminderQuotaMetric.allCases {
            var state = self[ReminderRuleID.quota(metric)]
            state.firedOccurrenceIDs = Set(v2.firedQuotaEventIDs.filter { $0.hasPrefix("codex.\(metric.rawValue).") })
            state.quotaLevelsWithoutWindow = Set(v2.lowQuotaLevelsWithoutWindow[metric] ?? [])
            self[ReminderRuleID.quota(metric)] = state
        }
        self[ReminderRuleID.sessionReset].previousCodexObservation = v2.previousCodexObservation
        self[ReminderRuleID.weeklyReset].firedOccurrenceIDs = v2.firedWeeklyResetEventIDs
        self[ReminderRuleID.weeklyReset].previousCodexObservation = v2.previousCodexObservation
        self[ReminderRuleID.resetCreditExpiry].firedOccurrenceIDs = v2.firedResetCreditExpiryEventIDs
        self[ReminderRuleID.deepSeekBalance].active = v2.deepSeekLowBalanceActive
        self[ReminderRuleID.dailyTokens] = ReminderRuleState(
            highestMilestone: v2.highestTokenMilestone,
            periodKey: v2.tokenDayKey
        )
        prepareForV5QuotaSemantics()
    }

    init(migrating v1: LegacyReminderRuleLedgerV1) {
        var converted = ReminderRuleLedgerV2()
        converted.firedQuotaEventIDs = Set(v1.firedQuotaEventIDs.map { eventID in
            let parts = eventID.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "codex" else { return eventID }
            return "\(parts[0]).\(parts[1]).30.\(parts[2])"
        })
        converted.lowQuotaLevelsWithoutWindow = Dictionary(uniqueKeysWithValues: v1.lowQuotaMetricsWithoutWindow.map {
            ($0, Set([30]))
        })
        converted.deepSeekLowBalanceActive = v1.deepSeekLowBalanceActive
        converted.tokenDayKey = v1.tokenDayKey
        converted.highestTokenMilestone = v1.highestTokenMilestone
        self.init(migrating: converted)
    }
}

enum ReminderLedgerCommitter {
    static func commit(
        previous: ReminderRuleLedger,
        candidate: ReminderRuleLedger,
        events: [ReminderEvent],
        acceptedIDs: Set<String>
    ) -> ReminderRuleLedger {
        var committed = previous
        let affectedRules = Set(events.map(\.ruleID))
        for (ruleID, var candidateState) in candidate.states {
            guard affectedRules.contains(ruleID) else {
                committed.states[ruleID] = candidateState
                continue
            }
            let acceptedForRule = Set(events.filter {
                $0.ruleID == ruleID && acceptedIDs.contains($0.id)
            }.map(\.id))
            guard !acceptedForRule.isEmpty else { continue }
            candidateState.firedOccurrenceIDs = previous[ruleID].firedOccurrenceIDs.union(acceptedForRule)
            committed.states[ruleID] = candidateState
        }
        return committed
    }
}

struct ReminderRuleLedgerV2: Codable, Equatable, Sendable {
    var firedQuotaEventIDs: Set<String> = []
    var lowQuotaLevelsWithoutWindow: [ReminderQuotaMetric: Set<Int>] = [:]
    var firedWeeklyResetEventIDs: Set<String> = []
    var firedResetCreditExpiryEventIDs: Set<String> = []
    var previousCodexObservation: ReminderCodexObservation?
    var deepSeekLowBalanceActive = false
    var tokenDayKey: String?
    var highestTokenMilestone = 0
}

struct LegacyReminderRuleLedgerV1: Codable, Equatable, Sendable {
    var firedQuotaEventIDs: Set<String> = []
    var lowQuotaMetricsWithoutWindow: Set<ReminderQuotaMetric> = []
    var deepSeekLowBalanceActive = false
    var tokenDayKey: String?
    var highestTokenMilestone = 0
}

enum ReminderRuleEvaluator {
    private static let quotaWindowIdentityTolerance: TimeInterval = 120

    static func evaluate(input: ReminderContext, ledger: inout ReminderRuleLedger) -> [ReminderEvent] {
        var events: [ReminderEvent] = []
        for rule in ReminderRuleCatalog.definitions.sorted(by: { $0.order < $1.order }) {
            var state = ledger[rule.id]
            if case .quotaWindowChange = rule.condition, !input.codexOfficialRouteIsActive {
                state.previousCodexObservation = nil
                ledger[rule.id] = state
                continue
            }
            if case .quotaThresholds = rule.condition, !input.codexOfficialRouteIsActive {
                state.previousQuotaPercent = nil
                state.previousQuotaRawResetAt = nil
                ledger[rule.id] = state
                continue
            }
            if case .balanceHysteresis = rule.condition, !input.deepSeekRouteIsActive {
                state.active = false
                ledger[rule.id] = state
                continue
            }
            guard rule.source.isFresh(in: input) else { continue }
            events.append(contentsOf: evaluate(rule, context: input, state: &state))
            ledger[rule.id] = state
        }
        // 周额度换窗时，5 小时额度也可能同批恢复。用户只需要一条更高层级的周额度提醒。
        if events.contains(where: { $0.ruleID == ReminderRuleID.weeklyReset }) {
            events.removeAll { $0.ruleID == ReminderRuleID.sessionReset }
        }
        return events
    }

    private static func evaluate(
        _ rule: ReminderRuleDefinition,
        context: ReminderContext,
        state: inout ReminderRuleState
    ) -> [ReminderEvent] {
        switch rule.condition {
        case let .quotaThresholds(metric, levels):
            return quotaEvents(rule, metric: metric, levels: levels, context: context, state: &state)
        case let .quotaWindowChange(metric, tolerance, requiredPercent, suppressUserInitiated):
            return quotaResetEvents(rule, metric: metric, tolerance: tolerance, requiredPercent: requiredPercent,
                                    suppressUserInitiated: suppressUserInitiated, context: context, state: &state)
        case let .expiryWindow(leadTime):
            return expiryEvents(rule, leadTime: leadTime, context: context, state: &state)
        case let .balanceHysteresis(triggerBelow, rearmAt, currency):
            return balanceEvents(rule, triggerBelow: triggerBelow, rearmAt: rearmAt,
                                 currency: currency, context: context, state: &state)
        case let .periodMilestone(size):
            return milestoneEvents(rule, size: size, context: context, state: &state)
        }
    }

    private static func quotaEvents(
        _ rule: ReminderRuleDefinition, metric: ReminderQuotaMetric, levels: [Int],
        context: ReminderContext, state: inout ReminderRuleState
    ) -> [ReminderEvent] {
        guard let quota = context.codexQuota?.value else { return [] }
        let remaining = metric == .session ? quota.sessionRemaining : quota.weeklyRemaining
        guard let remaining else { return [] }
        let resetAt = metric == .session ? quota.sessionResetAt : quota.weeklyResetAt
        let rawResetAt = (metric == .session ? quota.sessionRawResetAt : quota.weeklyRawResetAt) ?? resetAt
        let percent = QuotaRiskPolicy.displayedPercent(remaining)
        let thresholds = Array(Set(levels)).sorted()
        if state.quotaGeneration == nil { state.quotaGeneration = 0 }
        if state.quotaLevelsFired == nil { state.quotaLevelsFired = [] }
        let previousPercent = state.previousQuotaPercent
        let previousResetAt = state.previousQuotaRawResetAt
        let deadlineAdvanced = previousResetAt.flatMap { old in
            rawResetAt.map { $0.timeIntervalSince(old) > quotaWindowIdentityTolerance }
        } == true
        let fullRecovery = previousPercent.map { $0 < 100 } == true && percent == 100 && deadlineAdvanced
        let observedRollover = previousPercent.map { $0 < 100 && percent > max($0, 30) } == true
            && previousResetAt.map { $0 <= context.now } == true && deadlineAdvanced
        if fullRecovery || observedRollover {
            state.quotaGeneration = (state.quotaGeneration ?? 0) + 1
            state.quotaLevelsFired = []
        }
        state.previousQuotaPercent = percent
        state.previousQuotaRawResetAt = rawResetAt
        return thresholds.compactMap { level in
            guard percent <= level, state.quotaLevelsFired?.contains(level) != true else { return nil }
            let event = ReminderEvent.codexQuota(
                metric: metric, level: level, remainingPercent: percent,
                resetsAt: resetAt, generation: state.quotaGeneration ?? 0
            )
            state.quotaLevelsFired?.insert(level)
            for handledLevel in thresholds where handledLevel > level {
                state.quotaLevelsFired?.insert(handledLevel)
            }
            state.firedOccurrenceIDs.insert(event.id)
            return event
        }
    }

    private static func quotaResetEvents(
        _ rule: ReminderRuleDefinition, metric: ReminderQuotaMetric, tolerance: TimeInterval, requiredPercent: Int,
        suppressUserInitiated: Bool, context: ReminderContext, state: inout ReminderRuleState
    ) -> [ReminderEvent] {
        guard context.codexQuota?.value != nil else { return [] }
        let current = codexObservation(context, previousCount: state.previousCodexObservation?.resetCreditsAvailableCount)
        let currentPercent = metric == .session ? current.sessionDisplayedPercent : current.weeklyDisplayedPercent
        let previousPercent = metric == .session
            ? state.previousCodexObservation?.sessionDisplayedPercent
            : state.previousCodexObservation?.weeklyDisplayedPercent
        let isArmed = state.resetNotificationArmed ?? previousPercent.map { $0 < requiredPercent } ?? false
        defer {
            state.previousCodexObservation = current
            if let currentPercent {
                state.resetNotificationArmed = currentPercent < requiredPercent
            }
        }
        guard let previous = state.previousCodexObservation else { return [] }
        let previousResetAt = metric == .session ? previous.sessionResetAt : previous.weeklyResetAt
        let nextResetAt = metric == .session ? current.sessionResetAt : current.weeklyResetAt
        guard isArmed,
              let previousPercent,
              previousPercent < requiredPercent,
              currentPercent == requiredPercent,
              let previousResetAt,
              let nextResetAt,
              nextResetAt.timeIntervalSince(previousResetAt) > tolerance else { return [] }
        let resetCountDecreased = context.codexResetCredits?.isFresh == true
            && current.resetCreditsAvailableCount.map { count in
                previous.resetCreditsAvailableCount.map { count < $0 } ?? false
            } == true
        let userInitiated = current.sessionDisplayedPercent == 100
            && current.weeklyDisplayedPercent == 100 && resetCountDecreased
        guard !suppressUserInitiated || !userInitiated else { return [] }
        let early = current.observedAt < previousResetAt.addingTimeInterval(-tolerance)
        let event = ReminderEvent.codexQuotaReset(
            metric: metric,
            kind: early ? .early : .scheduled,
            previousResetAt: previousResetAt,
            nextResetAt: nextResetAt
        )
        return state.record(event.id, using: rule.deduplication) ? [event] : []
    }

    private static func expiryEvents(
        _ rule: ReminderRuleDefinition, leadTime: TimeInterval, context: ReminderContext,
        state: inout ReminderRuleState
    ) -> [ReminderEvent] {
        guard let credits = context.codexResetCredits?.value else { return [] }
        var occurrences: [Int: Int] = [:]
        return credits.expirations.sorted().compactMap { expiration in
            let secondsRemaining = expiration.timeIntervalSince(context.now)
            guard secondsRemaining > 0, secondsRemaining <= leadTime else { return nil }
            let timestamp = Int(expiration.timeIntervalSince1970)
            let occurrence = occurrences[timestamp, default: 0]
            occurrences[timestamp] = occurrence + 1
            let event = ReminderEvent.codexResetCreditExpiring(expiresAt: expiration, occurrence: occurrence)
            return state.record(event.id, using: rule.deduplication) ? event : nil
        }
    }

    private static func balanceEvents(
        _ rule: ReminderRuleDefinition, triggerBelow: Double, rearmAt: Double, currency: String,
        context: ReminderContext, state: inout ReminderRuleState
    ) -> [ReminderEvent] {
        guard context.deepSeekRouteIsActive else { state.active = false; return [] }
        guard let observation = context.deepSeekBalance, observation.value.currency.uppercased() == currency else { return [] }
        if observation.value.amount >= rearmAt { state.active = false; return [] }
        guard observation.value.amount < triggerBelow else { return [] }
        let activationID = String(Int(observation.fetchedAt.timeIntervalSince1970 * 1_000))
        let event = ReminderEvent.deepSeekBalance(amount: observation.value.amount, currency: observation.value.currency, activationID: activationID)
        return state.record(event.id, using: rule.deduplication) ? [event] : []
    }

    private static func milestoneEvents(
        _ rule: ReminderRuleDefinition, size: Int, context: ReminderContext, state: inout ReminderRuleState
    ) -> [ReminderEvent] {
        guard let observation = context.todayTokenTotal else { return [] }
        if state.periodKey != context.dayKey {
            state.periodKey = context.dayKey
            state.highestMilestone = 0
            state.firedOccurrenceIDs.removeAll()
        }
        guard observation.value >= size else { return [] }
        let milestone = observation.value / size
        guard milestone > state.highestMilestone else { return [] }
        let event = ReminderEvent.dailyTokens(total: observation.value, milestone: milestone, dayKey: context.dayKey)
        guard state.record(event.id, using: rule.deduplication) else { return [] }
        state.highestMilestone = milestone
        return [event]
    }

    private static func codexObservation(_ context: ReminderContext, previousCount: Int?) -> ReminderCodexObservation {
        let quota = context.codexQuota?.value
        let credits = context.codexResetCredits
        return ReminderCodexObservation(
            sessionDisplayedPercent: quota?.sessionRemaining.map(QuotaRiskPolicy.displayedPercent),
            sessionResetAt: quota.flatMap { $0.sessionRawResetAt ?? $0.sessionResetAt },
            sessionPeriodDuration: quota?.sessionPeriodDuration,
            weeklyDisplayedPercent: quota?.weeklyRemaining.map(QuotaRiskPolicy.displayedPercent),
            weeklyResetAt: quota.flatMap { $0.weeklyRawResetAt ?? $0.weeklyResetAt },
            weeklyPeriodDuration: quota?.weeklyPeriodDuration,
            resetCreditsAvailableCount: credits?.isFresh == true ? credits?.value.availableCount : previousCount,
            observedAt: context.codexQuota?.fetchedAt ?? context.now
        )
    }

}
