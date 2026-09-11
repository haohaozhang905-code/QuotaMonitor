import Foundation

@MainActor
final class ReminderCoordinator {
    private static let ledgerKey = "QuotaMonitor.reminderRuleLedger.v1"

    private let defaults: UserDefaults
    private let settings: ReminderSettings
    private let language: LanguageSettings
    private var ledger: ReminderRuleLedger
    var onEvents: (([ReminderEvent], [ReminderPresentation]) -> Void)?

    init(
        settings: ReminderSettings,
        language: LanguageSettings,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.language = language
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.ledgerKey),
           let decoded = try? JSONDecoder().decode(ReminderRuleLedger.self, from: data) {
            ledger = decoded
        } else {
            ledger = ReminderRuleLedger()
        }
    }

    func evaluate(store: QuotaStore) {
        guard settings.isEnabled else { return }
        let healthByID = Dictionary(uniqueKeysWithValues: store.dataSourceHealth.map { ($0.id, $0.state) })
        let codexQuotaIsFresh = healthByID[DataSourceCatalog.codexQuota] == .ready
        let deepSeekBalanceIsFresh = healthByID[DataSourceCatalog.deepSeekBalance] == .ready
        let tokenDataIsFresh = store.dataSourceHealth.contains {
            [.localToken, .cloudToken].contains($0.kind) && $0.state == .ready
        }
        let codex = codexQuotaIsFresh && store.codexRoute == .official
            ? store.providers.first { $0.providerId.lowercased() == "codex" }
            : nil
        let session = codex?.session
        let weekly = codex?.weekly
        let dayKey = DailyTokenUsage.dayKey(for: .now)
        let input = ReminderRuleInput(
            now: .now,
            dayKey: dayKey,
            codexSessionRemaining: session?.remainingPercent,
            codexSessionResetAt: session.flatMap { codex?.effectiveResetAt(for: $0) },
            codexWeeklyRemaining: weekly?.remainingPercent,
            codexWeeklyResetAt: weekly.flatMap { codex?.effectiveResetAt(for: $0) },
            deepSeekRouteIsActive: deepSeekBalanceIsFresh && (store.codexRoute == .deepseek || store.claudeUsesDeepSeek),
            deepSeekBalance: deepSeekBalanceIsFresh ? store.deepSeekBalance : nil,
            deepSeekCurrency: deepSeekBalanceIsFresh ? store.deepSeekCurrency : nil,
            todayTokenTotal: tokenDataIsFresh ? store.todayTokenUsage?.total : nil
        )

        let previousLedger = ledger
        let events = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        if ledger != previousLedger { saveLedger() }
        guard !events.isEmpty else { return }
        onEvents?(events, events.map(presentation))
    }

    private func presentation(for event: ReminderEvent) -> ReminderPresentation {
        let title: String
        switch event {
        case let .codexQuota(metric, _, _):
            title = language.text(metric == .session ? "reminder.codex.session.title" : "reminder.codex.weekly.title")
        case .deepSeekBalance:
            title = language.text("reminder.deepseek.title")
        case .dailyTokens:
            title = language.text("reminder.tokens.title")
        }
        return ReminderPresentation(
            id: "\(eventID(event)).\(UUID().uuidString)",
            title: title,
            details: [detail(event)],
            destination: event.destination
        )
    }

    private func detail(_ event: ReminderEvent) -> String {
        switch event {
        case let .codexQuota(metric, percent, resetsAt):
            let metricName = language.text(metric == .session ? "reminder.metric.session" : "reminder.metric.weekly")
            if let resetsAt {
                return language.text(
                    "reminder.codex.detailWithReset",
                    metricName,
                    percent,
                    QuotaFormatters.reset(resetsAt, language: language.language)
                )
            }
            return language.text("reminder.codex.detail", metricName, percent)
        case let .deepSeekBalance(amount, currency):
            return language.text("reminder.deepseek.detail", QuotaFormatters.money(amount, currency: currency))
        case let .dailyTokens(total, _):
            return language.text(
                "reminder.tokens.detail",
                QuotaFormatters.localizedTokens(total, language: language.language)
            )
        }
    }

    private func eventID(_ event: ReminderEvent) -> String {
        switch event {
        case let .codexQuota(metric, percent, _): "codex-\(metric.rawValue)-\(percent)"
        case .deepSeekBalance: "deepseek-balance"
        case let .dailyTokens(_, milestone): "tokens-\(milestone)"
        }
    }

    private func saveLedger() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.ledgerKey)
    }
}
