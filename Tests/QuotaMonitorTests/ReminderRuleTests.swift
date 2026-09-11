import Foundation
import Testing
@testable import QuotaMonitor

struct ReminderRuleTests {
    private let now = Date(timeIntervalSince1970: 1_788_880_000)

    @Test func coldStartBelowQuotaThresholdAlertsOncePerWindow() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(2 * 60 * 60)
        let input = makeInput(session: 0.20, sessionReset: reset)

        let first = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        let second = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)

        #expect(first == [.codexQuota(metric: .session, remainingPercent: 20, resetsAt: reset)])
        #expect(second.isEmpty)
    }

    @Test func quotaThresholdMatchesRoundedPercentageShownInUI() {
        var ledger = ReminderRuleLedger()
        let reset = now.addingTimeInterval(60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(session: 0.304, sessionReset: reset),
            ledger: &ledger
        )

        #expect(events == [.codexQuota(metric: .session, remainingPercent: 30, resetsAt: reset)])
    }

    @Test func simultaneousSessionAndWeeklyQuotasReturnOneBatchOfTwoEvents() {
        var ledger = ReminderRuleLedger()
        let sessionReset = now.addingTimeInterval(60 * 60)
        let weeklyReset = now.addingTimeInterval(4 * 24 * 60 * 60)
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(
                session: 0.20,
                sessionReset: sessionReset,
                weekly: 0.28,
                weeklyReset: weeklyReset
            ),
            ledger: &ledger
        )

        #expect(events.count == 2)
        #expect(events.contains(.codexQuota(metric: .session, remainingPercent: 20, resetsAt: sessionReset)))
        #expect(events.contains(.codexQuota(metric: .weekly, remainingPercent: 28, resetsAt: weeklyReset)))
    }

    @Test func aNewQuotaWindowCanAlertAgain() {
        var ledger = ReminderRuleLedger()
        let first = makeInput(session: 0.20, sessionReset: now.addingTimeInterval(60 * 60))
        let second = makeInput(session: 0.25, sessionReset: now.addingTimeInterval(6 * 60 * 60))

        #expect(ReminderRuleEvaluator.evaluate(input: first, ledger: &ledger).count == 1)
        #expect(ReminderRuleEvaluator.evaluate(input: second, ledger: &ledger).count == 1)
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
        let events = ReminderRuleEvaluator.evaluate(
            input: makeInput(deepSeekActive: true, balance: 1, currency: "USD"),
            ledger: &ledger
        )
        #expect(events.isEmpty)
    }

    @Test func tokenJumpEmitsOnlyHighestMilestoneAndDoesNotRepeat() {
        var ledger = ReminderRuleLedger()
        let input = makeInput(tokens: 320_000_000)

        let first = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)
        let second = ReminderRuleEvaluator.evaluate(input: input, ledger: &ledger)

        #expect(first == [.dailyTokens(total: 320_000_000, milestone: 3)])
        #expect(second.isEmpty)
        #expect(ledger.highestTokenMilestone == 3)
    }

    @Test func tokenMilestonesResetOnTheNextNaturalDay() {
        var ledger = ReminderRuleLedger(tokenDayKey: "2026-09-09", highestTokenMilestone: 3)
        let events = ReminderRuleEvaluator.evaluate(input: makeInput(tokens: 110_000_000), ledger: &ledger)

        #expect(events == [.dailyTokens(total: 110_000_000, milestone: 1)])
        #expect(ledger.tokenDayKey == "2026-09-10")
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

    private func makeInput(
        session: Double? = nil,
        sessionReset: Date? = nil,
        weekly: Double? = nil,
        weeklyReset: Date? = nil,
        deepSeekActive: Bool = false,
        balance: Double? = nil,
        currency: String? = nil,
        tokens: Int? = nil
    ) -> ReminderRuleInput {
        ReminderRuleInput(
            now: now,
            dayKey: "2026-09-10",
            codexSessionRemaining: session,
            codexSessionResetAt: sessionReset,
            codexWeeklyRemaining: weekly,
            codexWeeklyResetAt: weeklyReset,
            deepSeekRouteIsActive: deepSeekActive,
            deepSeekBalance: balance,
            deepSeekCurrency: currency,
            todayTokenTotal: tokens
        )
    }
}
