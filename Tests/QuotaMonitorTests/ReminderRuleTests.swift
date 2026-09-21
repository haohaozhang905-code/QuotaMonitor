import Foundation
import Testing
@testable import QuotaMonitor

private extension ReminderMessageTemplate {
    var allKeys: Set<String> {
        ([defaultKeys] + variants.values).reduce(into: Set<String>()) { keys, value in
            keys.insert(value.title)
            if let body = value.body { keys.insert(body) }
        }
    }
}

struct ReminderRuleTests {
    private let now = Date(timeIntervalSince1970: 1_788_880_000)

    @MainActor
    @Test func catalogHasUniqueOrderedRulesAndCompleteTranslations() {
        let rules = ReminderRuleCatalog.definitions
        #expect(Set(rules.map(\.id)).count == rules.count)
        #expect(rules.map(\.order) == rules.map(\.order).sorted())
        #expect(rules.allSatisfy { !$0.id.isEmpty && !$0.message.allKeys.isEmpty })

        let suite = "QuotaMonitorTests.ReminderCatalog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let language = LanguageSettings(defaults: defaults)
        let keys = rules.reduce(into: Set(["reminder.metric.session", "reminder.metric.weekly"])) {
            $0.formUnion($1.message.allKeys)
        }
        for locale in [AppLanguage.simplifiedChinese, .english] {
            language.language = locale
            for key in keys { #expect(language.text(key) != key) }
        }
    }

    @Test func v2LedgerMigratesAllReminderStateIntoRuleIDs() throws {
        let sessionReset = now.addingTimeInterval(60 * 60)
        let weeklyReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        let nextWeeklyReset = weeklyReset.addingTimeInterval(7 * 24 * 60 * 60)
        let expiration = now.addingTimeInterval(60 * 60)
        var v2 = ReminderRuleLedgerV2()
        v2.firedQuotaEventIDs = [
            "codex.session.30.\(Int(sessionReset.timeIntervalSince1970))",
            "codex.weekly.5.\(Int(weeklyReset.timeIntervalSince1970))",
        ]
        v2.lowQuotaLevelsWithoutWindow = [.session: [30]]
        v2.firedWeeklyResetEventIDs = ["codex.weekly-reset.\(Int(nextWeeklyReset.timeIntervalSince1970))"]
        v2.firedResetCreditExpiryEventIDs = [
            "codex.reset-credit-expiry.\(Int(expiration.timeIntervalSince1970)).0",
        ]
        v2.previousCodexObservation = ReminderCodexObservation(
            sessionDisplayedPercent: 30,
            sessionResetAt: sessionReset,
            sessionPeriodDuration: 5 * 60 * 60,
            weeklyDisplayedPercent: 40,
            weeklyResetAt: weeklyReset,
            weeklyPeriodDuration: 7 * 24 * 60 * 60,
            resetCreditsAvailableCount: 3,
            observedAt: now
        )
        v2.deepSeekLowBalanceActive = true
        v2.tokenDayKey = "2026-09-10"
        v2.highestTokenMilestone = 3

        let decodedV2 = try JSONDecoder().decode(ReminderRuleLedgerV2.self, from: JSONEncoder().encode(v2))
        var ledger = ReminderRuleLedger(migrating: decodedV2)
        #expect(ledger[ReminderRuleID.weeklyReset].previousCodexObservation?.weeklyResetAt == weeklyReset)
        #expect(ledger[ReminderRuleID.deepSeekBalance].active)
        #expect(ledger[ReminderRuleID.dailyTokens].periodKey == "2026-09-10")
        #expect(ledger[ReminderRuleID.dailyTokens].highestMilestone == 3)
        #expect(ledger[ReminderRuleID.quota(.session)].firedOccurrenceIDs.contains("codex.session.30.\(Int(sessionReset.timeIntervalSince1970))"))
        #expect(ledger[ReminderRuleID.quota(.weekly)].firedOccurrenceIDs.contains("codex.weekly.5.\(Int(weeklyReset.timeIntervalSince1970))"))
        #expect(ledger[ReminderRuleID.quota(.weekly)].quotaLevelsFired?.contains(5) == true)

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.04,
                sessionReset: sessionReset,
                weekly: 0.04,
                weeklyReset: nextWeeklyReset,
                weeklyDuration: 7 * 24 * 60 * 60,
                credits: credits(count: 2, expirations: [expiration, expiration]),
                deepSeekActive: true,
                balance: 4,
                currency: "CNY",
                tokens: 320_000_000
            ),
            ledger: &ledger
        )
        #expect(events == [
            .codexQuota(metric: .session, level: 5, remainingPercent: 4, resetsAt: sessionReset),
            .codexResetCreditExpiring(expiresAt: expiration, occurrence: 1),
        ])
    }

    @MainActor
    @Test func coordinatorMigratesV2LedgerToV5AndRetainsTheOldKey() throws {
        let suite = "QuotaMonitorTests.ReminderMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let v2 = ReminderRuleLedgerV2(firedQuotaEventIDs: ["codex.session.30.1788883600"])
        defaults.set(try JSONEncoder().encode(v2), forKey: "QuotaMonitor.reminderRuleLedger.v2")

        _ = ReminderCoordinator(
            settings: ReminderSettings(defaults: defaults),
            language: LanguageSettings(defaults: defaults),
            defaults: defaults
        )

        #expect(defaults.data(forKey: "QuotaMonitor.reminderRuleLedger.v2") != nil)
        let migratedData = try #require(defaults.data(forKey: "QuotaMonitor.reminderRuleLedger.v5"))
        let migrated = try JSONDecoder().decode(ReminderRuleLedger.self, from: migratedData)
        #expect(migrated[ReminderRuleID.quota(.session)].firedOccurrenceIDs.contains("codex.session.30.1788883600"))
    }

    @MainActor
    @Test func coordinatorMigratesV3ResetBaselineToV5WithoutArmingAFullQuota() throws {
        let suite = "QuotaMonitorTests.ReminderV4Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reset = now.addingTimeInterval(5 * 60 * 60)
        var v3 = ReminderRuleLedger()
        v3[ReminderRuleID.sessionReset].previousCodexObservation = ReminderCodexObservation(
            sessionDisplayedPercent: 100,
            sessionResetAt: reset,
            sessionPeriodDuration: 5 * 60 * 60,
            weeklyDisplayedPercent: nil,
            weeklyResetAt: nil,
            weeklyPeriodDuration: nil,
            resetCreditsAvailableCount: nil,
            observedAt: now
        )
        defaults.set(try JSONEncoder().encode(v3), forKey: "QuotaMonitor.reminderRuleLedger.v3")

        _ = ReminderCoordinator(
            settings: ReminderSettings(defaults: defaults),
            language: LanguageSettings(defaults: defaults),
            defaults: defaults
        )

        #expect(defaults.data(forKey: "QuotaMonitor.reminderRuleLedger.v3") != nil)
        let migratedData = try #require(defaults.data(forKey: "QuotaMonitor.reminderRuleLedger.v5"))
        let migrated = try JSONDecoder().decode(ReminderRuleLedger.self, from: migratedData)
        #expect(migrated[ReminderRuleID.sessionReset].resetNotificationArmed == false)
    }

    @Test func quotaThresholdsEscalateAndDeduplicatePerWindow() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(2 * 60 * 60)

        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.31, sessionReset: reset),
            ledger: &ledger
        ).isEmpty)

        let warning = ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.30, sessionReset: reset),
            ledger: &ledger
        )
        #expect(warning == [
            .codexQuota(metric: .session, level: 30, remainingPercent: 30, resetsAt: reset)
        ])
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.20, sessionReset: reset),
            ledger: &ledger
        ).isEmpty)

        let critical = ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.04, sessionReset: reset),
            ledger: &ledger
        )
        #expect(critical == [
            .codexQuota(metric: .session, level: 5, remainingPercent: 4, resetsAt: reset)
        ])
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0, sessionReset: reset),
            ledger: &ledger
        ).isEmpty)
    }

    @Test func coldStartInsideCriticalTierEmitsOnlyCriticalAndMarksWarningHandled() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.046, sessionReset: reset),
            ledger: &ledger
        )

        #expect(events == [
            .codexQuota(metric: .session, level: 5, remainingPercent: 5, resetsAt: reset)
        ])
        #expect(ledger[ReminderRuleID.quota(.session)].quotaLevelsFired == [5, 30])
    }

    @Test func quotaThresholdsUseTheSameRoundedPercentShownInTheInterface() {
        var warningLedger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(60 * 60)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.304, sessionReset: reset),
            ledger: &warningLedger
        ) == [
            .codexQuota(metric: .session, level: 30, remainingPercent: 30, resetsAt: reset)
        ])

        var criticalLedger = ReminderRuleLedger()
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.054, sessionReset: reset),
            ledger: &criticalLedger
        ) == [
            .codexQuota(metric: .session, level: 5, remainingPercent: 5, resetsAt: reset)
        ])
    }

    @Test func quotaThresholdDoesNotRepeatWhenResetTimestampDriftsByOneSecond() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(60 * 60)

        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.30, sessionReset: reset),
            ledger: &ledger
        ) == [
            .codexQuota(metric: .session, level: 30, remainingPercent: 30, resetsAt: reset)
        ])
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.29, sessionReset: reset.addingTimeInterval(1)),
            ledger: &ledger
        ).isEmpty)
    }

    @Test func quotaThresholdDoesNotRepeatAcrossThirtyMinutesOfRollingDeadlines() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(60 * 60)
        var warningCount = 0
        for minute in 0...30 {
            let events = ReminderRuleEvaluator.evaluate(
                input: makeInput(
                    now: now.addingTimeInterval(Double(minute * 60)),
                    session: 0.20,
                    sessionReset: reset.addingTimeInterval(Double(minute * 61))
                ),
                ledger: &ledger
            )
            warningCount += events.filter { $0.ruleID == ReminderRuleID.quota(.session) }.count
        }
        #expect(warningCount == 1)
    }

    @Test func crossingAnUnobservedWindowWithoutRecoveryStaysSilent() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(60)
        _ = ReminderRuleEvaluator.evaluate(input: makeInput(session: 0.20, sessionReset: oldReset), ledger: &ledger)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(6 * 60 * 60),
                session: 0.15,
                sessionReset: oldReset.addingTimeInterval(5 * 60 * 60)
            ),
            ledger: &ledger
        )
        #expect(events.isEmpty)
    }

    @Test func suppressedDeliveryDoesNotConsumeItsReminder() {
        let context = makeInput(session: 0.20, sessionReset: now.addingTimeInterval(60 * 60))
        let previous = ReminderRuleLedger()
        var candidate = previous
        let events = ReminderRuleEvaluator.evaluate(input: context, ledger: &candidate)
        #expect(events.count == 1)
        let suppressed = ReminderLedgerCommitter.commit(
            previous: previous, candidate: candidate, events: events, acceptedIDs: []
        )
        #expect(suppressed[ReminderRuleID.quota(.session)].quotaLevelsFired == nil)
        var retried = suppressed
        #expect(ReminderRuleEvaluator.evaluate(input: context, ledger: &retried) == events)
        let delivered = ReminderLedgerCommitter.commit(
            previous: previous, candidate: candidate, events: events, acceptedIDs: [events[0].id]
        )
        #expect(delivered[ReminderRuleID.quota(.session)].quotaLevelsFired == [30])
    }

    @MainActor
    @Test func v4QuotaMigrationKeepsCurrentWarningSuppressed() throws {
        let suite = "QuotaMonitorTests.V4Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = ReminderRuleLedger()
        var warning = legacy[ReminderRuleID.quota(.session)]
        warning.firedOccurrenceIDs = ["codex.session.30.\(Int(now.timeIntervalSince1970))"]
        legacy[ReminderRuleID.quota(.session)] = warning
        defaults.set(try JSONEncoder().encode(legacy), forKey: "QuotaMonitor.reminderRuleLedger.v4")
        let settings = ReminderSettings(defaults: defaults)
        let language = LanguageSettings(defaults: defaults)
        _ = ReminderCoordinator(settings: settings, language: language, defaults: defaults)
        let migrated = try JSONDecoder().decode(
            ReminderRuleLedger.self,
            from: #require(defaults.data(forKey: "QuotaMonitor.reminderRuleLedger.v5"))
        )
        #expect(migrated[ReminderRuleID.quota(.session)].quotaLevelsFired == [30])
        var next = migrated
        #expect(ReminderRuleEvaluator.evaluate(input: makeInput(session: 0.20), ledger: &next).isEmpty)
    }

    @Test func v5MigrationRearmsAfterPreviouslyObservedFullQuota() {
        var legacy = ReminderRuleLedger()
        var warning = legacy[ReminderRuleID.quota(.session)]
        warning.firedOccurrenceIDs = ["codex.session.30.1788883600"]
        legacy[ReminderRuleID.quota(.session)] = warning
        var reset = legacy[ReminderRuleID.sessionReset]
        reset.previousCodexObservation = ReminderCodexObservation(
            sessionDisplayedPercent: 100,
            sessionResetAt: now.addingTimeInterval(5 * 60 * 60),
            sessionPeriodDuration: 5 * 60 * 60,
            weeklyDisplayedPercent: nil,
            weeklyResetAt: nil,
            weeklyPeriodDuration: nil,
            resetCreditsAvailableCount: nil,
            observedAt: now
        )
        legacy[ReminderRuleID.sessionReset] = reset
        legacy.prepareForV5QuotaSemantics()
        #expect(legacy[ReminderRuleID.quota(.session)].quotaLevelsFired == [])
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.20, sessionReset: now.addingTimeInterval(5 * 60 * 60)),
            ledger: &legacy
        )
        #expect(events.contains { $0.ruleID == ReminderRuleID.quota(.session) })
    }

    @Test func simultaneousSessionAndWeeklyQuotasRemainIndependent() {
        var ledger = ReminderRuleLedger()
        let sessionReset = now.addingTimeInterval(60 * 60)
        let weeklyReset = now.addingTimeInterval(4 * 24 * 60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.20,
                sessionReset: sessionReset,
                weekly: 0.05,
                weeklyReset: weeklyReset
            ),
            ledger: &ledger
        )

        #expect(events == [
            .codexQuota(metric: .session, level: 30, remainingPercent: 20, resetsAt: sessionReset),
            .codexQuota(metric: .weekly, level: 5, remainingPercent: 5, resetsAt: weeklyReset),
        ])
    }

    @Test func aConfirmedFullRecoveryRearmsQuotaAlert() {
        var ledger = ReminderRuleLedger()
        let firstReset = now.addingTimeInterval(60 * 60)
        let secondReset = now.addingTimeInterval(6 * 60 * 60)

        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.20, sessionReset: firstReset),
            ledger: &ledger
        ).count == 1)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 1, sessionReset: secondReset),
            ledger: &ledger
        ).count == 1)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.25, sessionReset: secondReset),
            ledger: &ledger
        ).count == 1)
    }

    @Test func missingResetWindowDoesNotRearmWithoutEvidence() {
        var ledger = ReminderRuleLedger()
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.20),
            ledger: &ledger
        ).count == 1)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.04),
            ledger: &ledger
        ).count == 1)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.20),
            ledger: &ledger
        ).isEmpty)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.31),
            ledger: &ledger
        ).isEmpty)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.30),
            ledger: &ledger
        ).isEmpty)
    }

    @Test func firstWeeklyObservationSeedsBaselineWithoutResetNotification() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 1, weeklyReset: reset, weeklyDuration: 7 * 24 * 60 * 60),
            ledger: &ledger
        )

        #expect(events.isEmpty)
        #expect(ledger[ReminderRuleID.weeklyReset].previousCodexObservation?.weeklyResetAt == reset)
    }

    @Test func scheduledSessionResetIsDetectedWhenWindowAdvances() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(60)
        let nextReset = oldReset.addingTimeInterval(5 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.40,
                sessionReset: oldReset,
                sessionDuration: 5 * 60 * 60
            ),
            ledger: &ledger
        )

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(90),
                session: 1,
                sessionReset: nextReset,
                sessionDuration: 5 * 60 * 60
            ),
            ledger: &ledger
        )
        #expect(events == [
            .codexQuotaReset(
                metric: .session,
                kind: .scheduled,
                previousResetAt: oldReset,
                nextResetAt: nextReset
            )
        ])
        #expect(ledger[ReminderRuleID.sessionReset].firedOccurrenceIDs.contains(
            "codex.session-reset.\(Int(oldReset.timeIntervalSince1970))"
        ))
    }

    @Test func scheduledWeeklyResetIsDetectedWhenWindowAdvances() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(60)
        let nextReset = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 0.40, weeklyReset: oldReset, weeklyDuration: 7 * 24 * 60 * 60),
            ledger: &ledger
        )

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(90),
                weekly: 1,
                weeklyReset: nextReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        )
        #expect(events == [
            .codexQuotaReset(metric: .weekly, kind: .scheduled, previousResetAt: oldReset, nextResetAt: nextReset)
        ])
    }

    @Test func resetTimeChangesAtOneHundredPercentAreSilent() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        let nextReset = now.addingTimeInterval(7 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 1, weeklyReset: oldReset, weeklyDuration: 7 * 24 * 60 * 60),
            ledger: &ledger
        )

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(60),
                weekly: 1,
                weeklyReset: nextReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        )
        #expect(events.isEmpty)
        #expect(ledger[ReminderRuleID.weeklyReset].resetNotificationArmed == false)
    }

    @Test func earlyWeeklyResetRequiresAnObservableRecoveryToOneHundredPercent() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        let nextReset = now.addingTimeInterval(7 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 0.44, weeklyReset: oldReset, weeklyDuration: 7 * 24 * 60 * 60),
            ledger: &ledger
        )

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(60),
                weekly: 1,
                weeklyReset: nextReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        )

        #expect(events == [
            .codexQuotaReset(metric: .weekly, kind: .early, previousResetAt: oldReset, nextResetAt: nextReset)
        ])
        #expect(ledger[ReminderRuleID.weeklyReset].resetNotificationArmed == false)
    }

    @Test func wakeAfterScheduledResetAlertsOnceAndLaterWindowAdjustmentsStaySilent() throws {
        var ledger = ReminderRuleLedger()
        let scheduledReset = now.addingTimeInterval(60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.05,
                sessionReset: scheduledReset,
                sessionDuration: 5 * 60 * 60
            ),
            ledger: &ledger
        )

        let wakeTime = now.addingTimeInterval(90)
        let firstNextReset = wakeTime.addingTimeInterval(5 * 60 * 60)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: wakeTime,
                session: 1,
                sessionReset: firstNextReset,
                sessionDuration: 5 * 60 * 60
            ),
            ledger: &ledger
        ) == [
            .codexQuotaReset(
                metric: .session,
                kind: .scheduled,
                previousResetAt: scheduledReset,
                nextResetAt: firstNextReset
            )
        ])

        ledger = try JSONDecoder().decode(ReminderRuleLedger.self, from: JSONEncoder().encode(ledger))

        for offset in [15.0, 60.0, 4 * 60 * 60.0] {
            let observationTime = wakeTime.addingTimeInterval(offset)
            #expect(ReminderRuleEvaluator.evaluate(
                input: makeInput(
                    now: observationTime,
                    session: 1,
                    sessionReset: observationTime.addingTimeInterval(5 * 60 * 60),
                    sessionDuration: 5 * 60 * 60
                ),
                ledger: &ledger
            ).isEmpty)
        }
    }

    @Test func simultaneousEarlySessionAndWeeklyResetEmitsOnlyWeeklyReminder() {
        var ledger = ReminderRuleLedger()
        let oldSessionReset = now.addingTimeInterval(2 * 60 * 60)
        let oldWeeklyReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.40,
                sessionReset: oldSessionReset,
                sessionDuration: 5 * 60 * 60,
                weekly: 0.40,
                weeklyReset: oldWeeklyReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        )

        let nextSessionReset = now.addingTimeInterval(5 * 60 * 60)
        let nextWeeklyReset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(60),
                session: 1,
                sessionReset: nextSessionReset,
                sessionDuration: 5 * 60 * 60,
                weekly: 1,
                weeklyReset: nextWeeklyReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        )

        #expect(events == [
            .codexQuotaReset(
                metric: .weekly,
                kind: .early,
                previousResetAt: oldWeeklyReset,
                nextResetAt: nextWeeklyReset
            )
        ])
        #expect(ledger[ReminderRuleID.sessionReset].firedOccurrenceIDs.contains(
            "codex.session-reset.\(Int(oldSessionReset.timeIntervalSince1970))"
        ))
    }

    @Test func weeklyResetRequiresDisplayedOneHundredPercent() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 0.50, weeklyReset: oldReset),
            ledger: &ledger
        )
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 0.99, weeklyReset: oldReset.addingTimeInterval(7 * 24 * 60 * 60)),
            ledger: &ledger
        )
        #expect(events.isEmpty)
    }

    @Test func confirmedUserResetSuppressesWeeklyResetNotification() {
        var ledger = ReminderRuleLedger()
        let oldSessionReset = now.addingTimeInterval(2 * 60 * 60)
        let oldWeeklyReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.30,
                sessionReset: oldSessionReset,
                weekly: 0.20,
                weeklyReset: oldWeeklyReset,
                weeklyDuration: 7 * 24 * 60 * 60,
                credits: credits(count: 3)
            ),
            ledger: &ledger
        )

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(60),
                session: 1,
                sessionReset: oldSessionReset.addingTimeInterval(5 * 60 * 60),
                weekly: 1,
                weeklyReset: now.addingTimeInterval(7 * 24 * 60 * 60),
                weeklyDuration: 7 * 24 * 60 * 60,
                credits: credits(count: 2, fetchedAt: now.addingTimeInterval(60))
            ),
            ledger: &ledger
        )
        #expect(events.isEmpty)
    }

    @Test func failedQuotaRefreshNeitherTriggersNorOverwritesResetBaseline() {
        var ledger = ReminderRuleLedger()
        let oldReset = now.addingTimeInterval(60)
        let nextReset = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 0.40, weeklyReset: oldReset, weeklyDuration: 7 * 24 * 60 * 60),
            ledger: &ledger
        )
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(60),
                quotaFresh: false,
                weekly: 1,
                weeklyReset: nextReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        ).isEmpty)

        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                now: now.addingTimeInterval(90),
                weekly: 1,
                weeklyReset: nextReset,
                weeklyDuration: 7 * 24 * 60 * 60
            ),
            ledger: &ledger
        )
        #expect(events == [
            .codexQuotaReset(metric: .weekly, kind: .scheduled, previousResetAt: oldReset, nextResetAt: nextReset)
        ])
    }

    @Test func leavingOfficialRouteClearsWeeklyResetBaseline() {
        var ledger = ReminderRuleLedger()
        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(weekly: 0.40, weeklyReset: now.addingTimeInterval(60)),
            ledger: &ledger
        )
        #expect(ledger[ReminderRuleID.weeklyReset].previousCodexObservation != nil)

        _ = ReminderRuleEvaluator.evaluate(
            input: makeInput(officialRoute: false, quotaFresh: false),
            ledger: &ledger
        )
        #expect(ledger[ReminderRuleID.weeklyReset].previousCodexObservation == nil)
    }

    @Test func resetCreditExpiryAlertsAtTwentyFourHoursAndOnlyOnce() {
        var ledger = ReminderRuleLedger()
        let expiration = now.addingTimeInterval(24 * 60 * 60)
        let input = makeInput(credits: credits(count: 1, expirations: [expiration]))

        let first = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        let second = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        #expect(first == [.codexResetCreditExpiring(expiresAt: expiration, occurrence: 0)])
        #expect(second.isEmpty)
    }

    @Test func resetCreditExpiryOutsideWindowOrAlreadyExpiredDoesNotAlert() {
        var ledger = ReminderRuleLedger()
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(credits: credits(
                count: 2,
                expirations: [
                    now.addingTimeInterval(24 * 60 * 60 + 1),
                    now.addingTimeInterval(-1),
                ]
            )),
            ledger: &ledger
        )
        #expect(events.isEmpty)
    }

    @Test func resetCreditsWithTheSameExpirationAlertIndividually() {
        var ledger = ReminderRuleLedger()
        let expiration = now.addingTimeInterval(60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(credits: credits(count: 2, expirations: [expiration, expiration])),
            ledger: &ledger
        )
        #expect(events == [
            .codexResetCreditExpiring(expiresAt: expiration, occurrence: 0),
            .codexResetCreditExpiring(expiresAt: expiration, occurrence: 1),
        ])
    }

    @Test func missingFreshResetCreditSnapshotDoesNotAlert() {
        var ledger = ReminderRuleLedger()
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(credits: nil),
            ledger: &ledger
        ).isEmpty)
    }

    @Test func legacyLedgerMigrationPreservesThirtyPercentDedupAndAllowsFivePercent() {
        let reset = now.addingTimeInterval(60 * 60)
        let legacy = LegacyReminderRuleLedgerV1(
            firedQuotaEventIDs: ["codex.session.\(Int(reset.timeIntervalSince1970))"],
            lowQuotaMetricsWithoutWindow: [.weekly],
            deepSeekLowBalanceActive: true,
            tokenDayKey: "2026-09-10",
            highestTokenMilestone: 3
        )
        var ledger = ReminderRuleLedger(migrating: legacy)
        #expect(ledger[ReminderRuleID.deepSeekBalance].active)

        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.20,
                sessionReset: reset,
                deepSeekActive: true,
                balance: 5.5,
                currency: "CNY"
            ),
            ledger: &ledger
        ).isEmpty)
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.04,
                sessionReset: reset,
                deepSeekActive: true,
                balance: 5.5,
                currency: "CNY"
            ),
            ledger: &ledger
        ) == [
            .codexQuota(metric: .session, level: 5, remainingPercent: 4, resetsAt: reset)
        ])
        #expect(ledger[ReminderRuleID.dailyTokens].highestMilestone == 3)
    }

    @Test func deepSeekLowBalanceNeedsActiveRouteAndRearmsAfterRecovery() {
        var ledger = ReminderRuleLedger()
        let low = makeInput(deepSeekActive: true, balance: 4.8, currency: "CNY")
        let recovered = makeInput(deepSeekActive: true, balance: 6.0, currency: "CNY")

        #expect(ReminderRuleEvaluator.evaluate(input: low, ledger: &ledger).count == 1)
        #expect(ReminderRuleEvaluator.evaluate(input: low, ledger: &ledger).isEmpty)
        #expect(ReminderRuleEvaluator.evaluate(input: recovered, ledger: &ledger).isEmpty)
        #expect(ReminderRuleEvaluator.evaluate(input: low, ledger: &ledger).count == 1)

        var inactiveLedger = ReminderRuleLedger()
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(deepSeekActive: false, balance: 1, currency: "CNY"),
            ledger: &inactiveLedger
        ).isEmpty)
    }

    @Test func nonCNYBalanceDoesNotUseTheFiveYuanRule() {
        var ledger = ReminderRuleLedger()
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(deepSeekActive: true, balance: 1, currency: "USD"),
            ledger: &ledger
        ).isEmpty)
    }

    @Test func tokenJumpEmitsOnlyHighestMilestoneAndDoesNotRepeat() {
        var ledger = ReminderRuleLedger()
        let input = makeInput(tokens: 320_000_000)

        let first = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        let second = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        #expect(first == [.dailyTokens(total: 320_000_000, milestone: 3, dayKey: "2026-09-10")])
        #expect(second.isEmpty)
        #expect(ledger[ReminderRuleID.dailyTokens].highestMilestone == 3)
    }

    @Test func tokenMilestoneTriggersAtTheExactTwoHundredMillionBoundary() {
        var ledger = ReminderRuleLedger()

        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(tokens: 199_999_999),
            ledger: &ledger
        ) == [.dailyTokens(total: 199_999_999, milestone: 1, dayKey: "2026-09-10")])
        #expect(ReminderRuleEvaluator.evaluate(
            input: makeInput(tokens: 200_000_000),
            ledger: &ledger
        ) == [.dailyTokens(total: 200_000_000, milestone: 2, dayKey: "2026-09-10")])
    }

    @Test func tokenMilestonesResetOnTheNextNaturalDay() {
        var ledger = ReminderRuleLedger()
        ledger[ReminderRuleID.dailyTokens] = ReminderRuleState(highestMilestone: 3, periodKey: "2026-09-09")
        let events = ReminderRuleEvaluator.evaluate(input: makeInput(tokens: 110_000_000), ledger: &ledger)

        #expect(events == [.dailyTokens(total: 110_000_000, milestone: 1, dayKey: "2026-09-10")])
        #expect(ledger[ReminderRuleID.dailyTokens].periodKey == "2026-09-10")
    }

    @MainActor
    @Test func localizedCodexPresentationsUseTheApprovedChineseCopy() {
        let suite = "QuotaMonitorTests.ReminderCopy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: LanguageSettings.storageKey)
        let language = LanguageSettings(defaults: defaults)
        let coordinator = ReminderCoordinator(
            settings: ReminderSettings(defaults: defaults),
            language: language,
            defaults: defaults
        )
        let reset = Date.now.addingTimeInterval(60 * 60)
        let formattedReset = QuotaFormatters.reset(reset, language: .simplifiedChinese)

        let quota = coordinator.presentation(for: .codexQuota(
            metric: .session,
            level: 30,
            remainingPercent: 28,
            resetsAt: reset
        ))
        #expect(quota.title == "需关注：Codex 5小时额度仅剩28%")
        #expect(quota.body == "将于\(formattedReset) 重置")
        #expect(quota.tone == .warning)

        let sessionReset = coordinator.presentation(for: .codexQuotaReset(
            metric: .session,
            kind: .scheduled,
            previousResetAt: reset,
            nextResetAt: reset
        ))
        #expect(sessionReset.title == "Codex 5小时额度已重置")
        #expect(sessionReset.body == "5小时额度已恢复至100%，下次将于\(formattedReset) 重置")

        let weeklyReset = coordinator.presentation(for: .codexQuotaReset(
            metric: .weekly,
            kind: .scheduled,
            previousResetAt: reset,
            nextResetAt: reset
        ))
        #expect(weeklyReset.title == "Codex 周额度已重置")
        #expect(weeklyReset.body == "周额度已恢复至100%，下次将于\(formattedReset) 重置")

        let earlyReset = coordinator.presentation(for: .codexQuotaReset(
            metric: .weekly,
            kind: .early,
            previousResetAt: reset,
            nextResetAt: reset.addingTimeInterval(7 * 24 * 60 * 60)
        ))
        #expect(earlyReset.title == "Codex 周额度已提前重置")
        #expect(earlyReset.body == "周额度已恢复至100%，原定于\(formattedReset) 重置")

        let expiry = coordinator.presentation(for: .codexResetCreditExpiring(expiresAt: reset, occurrence: 0))
        #expect(expiry.title == "1个 Codex 重置机会即将到期")
        #expect(expiry.body == "将于\(formattedReset) 到期")
    }

    @MainActor
    @Test func resetCreditReminderDataMustComeFromTheExactQuotaRefreshBatch() {
        let fetchedAt = Date(timeIntervalSince1970: 1_788_880_000)
        let currentBatch = CodexResetCredits(
            availableCount: 2,
            expirations: [fetchedAt.addingTimeInterval(60 * 60)],
            fetchedAt: fetchedAt
        )
        let staleBatch = CodexResetCredits(
            availableCount: 1,
            expirations: [fetchedAt.addingTimeInterval(60 * 60)],
            fetchedAt: fetchedAt.addingTimeInterval(-1)
        )

        #expect(ReminderCoordinator.alignedResetCredits(currentBatch, providerFetchedAt: fetchedAt)?.availableCount == 2)
        #expect(ReminderCoordinator.alignedResetCredits(staleBatch, providerFetchedAt: fetchedAt) == nil)
        #expect(ReminderCoordinator.alignedResetCredits(currentBatch, providerFetchedAt: nil) == nil)
    }

    @MainActor
    @Test func localizedCodexPresentationsHaveEnglishEquivalents() {
        let suite = "QuotaMonitorTests.ReminderCopy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.english.rawValue, forKey: LanguageSettings.storageKey)
        let language = LanguageSettings(defaults: defaults)
        let coordinator = ReminderCoordinator(
            settings: ReminderSettings(defaults: defaults),
            language: language,
            defaults: defaults
        )

        let presentation = coordinator.presentation(for: .codexQuota(
            metric: .weekly,
            level: 5,
            remainingPercent: 4,
            resetsAt: nil
        ))
        #expect(presentation.title == "High risk: Codex weekly quota has 4% left")
        #expect(presentation.details.isEmpty)
        #expect(presentation.tone == .critical)
    }

    @MainActor
    @Test func newInstallEnablesReminderPreferencesByDefault() {
        let suite = "QuotaMonitorTests.ReminderSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ReminderSettings(defaults: defaults)

        #expect(settings.isEnabled)
        #expect(settings.prefersSystemNotifications)
    }

    @MainActor
    @Test func notificationPreferenceStaysOnWhileWaitingForSystemAuthorization() {
        let suite = "QuotaMonitorTests.ReminderSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ReminderSettings.systemNotificationsKey)
        let settings = ReminderSettings(defaults: defaults)

        settings.updateSystemAuthorization(.notRequested)
        #expect(settings.prefersSystemNotifications)
        #expect(defaults.bool(forKey: ReminderSettings.systemNotificationsKey))
    }

    @MainActor
    @Test func deniedSystemAuthorizationTurnsNotificationPreferenceOff() {
        let suite = "QuotaMonitorTests.ReminderSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ReminderSettings.systemNotificationsKey)
        let settings = ReminderSettings(defaults: defaults)

        settings.updateSystemAuthorization(.denied)
        #expect(settings.prefersSystemNotifications == false)
        #expect(defaults.bool(forKey: ReminderSettings.systemNotificationsKey) == false)
    }

    private func credits(
        count: Int,
        expirations: [Date] = [],
        fetchedAt: Date? = nil
    ) -> ReminderResetCreditsInput {
        ReminderResetCreditsInput(
            availableCount: count,
            expirations: expirations,
            fetchedAt: fetchedAt ?? now
        )
    }

    private func makeInput(
        now inputNow: Date? = nil,
        officialRoute: Bool = true,
        quotaFresh: Bool = true,
        session: Double? = nil,
        sessionReset: Date? = nil,
        sessionDuration: TimeInterval? = nil,
        weekly: Double? = nil,
        weeklyReset: Date? = nil,
        weeklyDuration: TimeInterval? = nil,
        credits: ReminderResetCreditsInput? = nil,
        deepSeekActive: Bool = false,
        balance: Double? = nil,
        currency: String? = nil,
        tokens: Int? = nil
    ) -> ReminderContext {
        let observationTime = inputNow ?? now
        let quota = ReminderCodexQuotaSnapshot(
            sessionRemaining: session,
            sessionResetAt: sessionReset,
            sessionPeriodDuration: sessionDuration,
            weeklyRemaining: weekly,
            weeklyResetAt: weeklyReset,
            weeklyPeriodDuration: weeklyDuration
        )
        let deepSeekBalance: Observed<ReminderDeepSeekBalance>?
        if let balance, let currency {
            deepSeekBalance = Observed(
                value: ReminderDeepSeekBalance(amount: balance, currency: currency),
                fetchedAt: observationTime,
                isFresh: true
            )
        } else {
            deepSeekBalance = nil
        }
        return ReminderContext(
            now: observationTime,
            dayKey: "2026-09-10",
            codexOfficialRouteIsActive: officialRoute,
            codexQuota: quotaFresh ? Observed(value: quota, fetchedAt: observationTime, isFresh: true) : nil,
            codexResetCredits: credits.map { Observed(value: $0, fetchedAt: $0.fetchedAt, isFresh: true) },
            deepSeekRouteIsActive: deepSeekActive,
            deepSeekBalance: deepSeekBalance,
            todayTokenTotal: tokens.map { Observed(value: $0, fetchedAt: observationTime, isFresh: true) }
        )
    }
}
