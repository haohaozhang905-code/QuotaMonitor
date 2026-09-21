import Foundation

@MainActor
final class ReminderCoordinator {
    private static let ledgerKey = "QuotaMonitor.reminderRuleLedger.v5"
    private static let v4LedgerKey = "QuotaMonitor.reminderRuleLedger.v4"
    private static let v3LedgerKey = "QuotaMonitor.reminderRuleLedger.v3"
    private static let v2LedgerKey = "QuotaMonitor.reminderRuleLedger.v2"
    private static let v1LedgerKey = "QuotaMonitor.reminderRuleLedger.v1"
    private let defaults: UserDefaults
    private let settings: ReminderSettings
    private let language: LanguageSettings
    private var ledger: ReminderRuleLedger
    var onEvents: (([ReminderEvent], [ReminderPresentation]) async -> Set<String>)?

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
        } else if let data = defaults.data(forKey: Self.v4LedgerKey),
                  var legacy = try? JSONDecoder().decode(ReminderRuleLedger.self, from: data) {
            legacy.prepareForV5QuotaSemantics()
            ledger = legacy
            persist(ledger)
        } else if let data = defaults.data(forKey: Self.v3LedgerKey),
                  var legacy = try? JSONDecoder().decode(ReminderRuleLedger.self, from: data) {
            legacy.prepareForV4ResetSemantics()
            legacy.prepareForV5QuotaSemantics()
            ledger = legacy
            persist(ledger)
        } else if let data = defaults.data(forKey: Self.v2LedgerKey),
                  let legacyV2 = try? JSONDecoder().decode(ReminderRuleLedgerV2.self, from: data) {
            var migrated = ReminderRuleLedger(migrating: legacyV2)
            migrated.prepareForV4ResetSemantics()
            migrated.prepareForV5QuotaSemantics()
            ledger = migrated
            persist(ledger)
        } else if let data = defaults.data(forKey: Self.v1LedgerKey),
                  let legacyV1 = try? JSONDecoder().decode(LegacyReminderRuleLedgerV1.self, from: data) {
            var migrated = ReminderRuleLedger(migrating: legacyV1)
            migrated.prepareForV4ResetSemantics()
            migrated.prepareForV5QuotaSemantics()
            ledger = migrated
            persist(ledger)
        } else {
            ledger = ReminderRuleLedger()
        }
    }

    func evaluate(store: QuotaStore) async {
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
        let resetCredits = Self.alignedResetCredits(store.codexResetCredits, providerFetchedAt: codex?.fetchedAt)
        let dayKey = DailyTokenUsage.dayKey(for: .now)
        let quotaObservation = codex.map { provider in
            Observed(
                value: ReminderCodexQuotaSnapshot(
                    sessionRemaining: session?.remainingPercent,
                    sessionResetAt: session.flatMap { provider.effectiveResetAt(for: $0) },
                    sessionPeriodDuration: session?.periodDurationMs.map { $0 / 1_000 },
                    weeklyRemaining: weekly?.remainingPercent,
                    weeklyResetAt: weekly.flatMap { provider.effectiveResetAt(for: $0) },
                    weeklyPeriodDuration: weekly?.periodDurationMs.map { $0 / 1_000 },
                    sessionRawResetAt: session?.resetsAt,
                    weeklyRawResetAt: weekly?.resetsAt
                ),
                fetchedAt: provider.fetchedAt ?? store.lastUpdated ?? .now,
                isFresh: true
            )
        }
        let resetCreditObservation = resetCredits.map {
            Observed(value: $0, fetchedAt: $0.fetchedAt, isFresh: true)
        }
        let deepSeekRouteIsActive = deepSeekBalanceIsFresh && (store.codexRoute == .deepseek || store.claudeUsesDeepSeek)
        let deepSeekObservation: Observed<ReminderDeepSeekBalance>?
        if deepSeekRouteIsActive, let balance = store.deepSeekBalance, let currency = store.deepSeekCurrency {
            deepSeekObservation = Observed(
                value: ReminderDeepSeekBalance(amount: balance, currency: currency),
                fetchedAt: store.lastUpdated ?? .now,
                isFresh: true
            )
        } else {
            deepSeekObservation = nil
        }
        let tokenObservation: Observed<Int>? = tokenDataIsFresh
            ? store.todayTokenUsage.map {
                Observed(value: $0.total, fetchedAt: store.lastTokenUpdatedAt ?? .now, isFresh: true)
            }
            : nil

        let context = ReminderContext(
            now: .now,
            dayKey: dayKey,
            codexOfficialRouteIsActive: store.codexRoute == .official,
            codexQuota: quotaObservation,
            codexResetCredits: resetCreditObservation,
            deepSeekRouteIsActive: deepSeekRouteIsActive,
            deepSeekBalance: deepSeekObservation,
            todayTokenTotal: tokenObservation
        )
        let previousLedger = ledger
        var candidateLedger = ledger
        let events = ReminderRuleEvaluator.evaluate(input: context, ledger: &candidateLedger)
        var accepted: Set<String> = []
        if !events.isEmpty {
            accepted = await onEvents?(events, events.map(presentation)) ?? []
        }
        ledger = ReminderLedgerCommitter.commit(
            previous: previousLedger,
            candidate: candidateLedger,
            events: events,
            acceptedIDs: accepted
        )
        if ledger != previousLedger { persist(ledger) }
    }

    func presentation(for event: ReminderEvent) -> ReminderPresentation {
        let title = language.text(
            event.message.titleKey,
            arguments: event.message.titleArguments.map { $0.resolve(language: language) }
        )
        let details = event.message.bodyKey.map { key in
            language.text(key, arguments: event.message.bodyArguments.map { $0.resolve(language: language) })
        }.map { [$0] } ?? []
        return ReminderPresentation(
            id: event.id,
            title: title,
            details: details,
            destination: event.destination,
            tone: event.tone
        )
    }

    private func persist(_ ledger: ReminderRuleLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.ledgerKey)
    }

    static func alignedResetCredits(
        _ resetCredits: CodexResetCredits?,
        providerFetchedAt: Date?
    ) -> ReminderResetCreditsInput? {
        guard let resetCredits, let providerFetchedAt,
              resetCredits.fetchedAt == providerFetchedAt else { return nil }
        return ReminderResetCreditsInput(
            availableCount: resetCredits.availableCount,
            expirations: resetCredits.expirations,
            fetchedAt: resetCredits.fetchedAt
        )
    }
}
