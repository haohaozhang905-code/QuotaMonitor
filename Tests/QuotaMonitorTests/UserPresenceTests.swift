import Testing
@testable import QuotaMonitor

struct UserPresenceTests {
    @Test func notificationGateRequiresAnUnlockedAwakeDisplay() {
        var state = ReminderPresenceState()
        #expect(!state.allowsNotification(hasAwakeDisplay: true))
        state.lockState = .unlocked
        #expect(state.allowsNotification(hasAwakeDisplay: true))
        #expect(!state.allowsNotification(hasAwakeDisplay: false))
        state.screenSleeping = true
        #expect(state.allowsNotification(hasAwakeDisplay: true)) // external screen remains in use
        #expect(!state.allowsNotification(hasAwakeDisplay: false))
        state.screenSleeping = false
        state.systemSleeping = true
        #expect(!state.allowsNotification(hasAwakeDisplay: true))
        state.systemSleeping = false
        state.lockState = .locked
        #expect(!state.allowsNotification(hasAwakeDisplay: true))
    }
}
