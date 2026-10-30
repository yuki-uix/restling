import XCTest
@testable import BreaktimeApp

final class PresenceMonitorTests: XCTestCase {
    func testUnknownStartSuppressesUntilAnActualAppInteraction() {
        var state = PresenceState()
        XCTAssertTrue(state.lockedOrSessionUnavailable)
        state.observeSystem(locked: nil, onConsole: true)
        XCTAssertTrue(state.lockedOrSessionUnavailable, "On-console alone does not prove unlocked.")
        state.confirmUserInteraction()
        XCTAssertFalse(state.lockedOrSessionUnavailable)
        state.observeSystem(locked: nil, onConsole: true)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }

    func testLockNotificationSurvivesStaleUnlockedPollAndUserInteraction() {
        var state = PresenceState()
        state.observeSystem(locked: false, onConsole: true)
        state.receiveLockNotification(locked: true)
        state.observeSystem(locked: false, onConsole: true)
        state.confirmUserInteraction()
        XCTAssertTrue(state.lockNotificationLatched)
        XCTAssertTrue(state.lockedOrSessionUnavailable)
        XCTAssertEqual(state.systemLocked, true)
    }

    func testExplicitUnlockClearsLatchAndSurvivesMissingPollData() {
        var state = PresenceState()
        state.receiveLockNotification(locked: true)
        state.receiveLockNotification(locked: false)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
        state.observeSystem(locked: nil, onConsole: nil)
        XCTAssertFalse(state.lockNotificationLatched)
        XCTAssertEqual(state.systemLocked, false)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }

    func testSystemReadCanDetectLockAndUnlockWithoutAnExplicitLockNotification() {
        var state = PresenceState()
        state.observeSystem(locked: true, onConsole: true)
        state.confirmUserInteraction()
        XCTAssertTrue(state.lockedOrSessionUnavailable)
        state.observeSystem(locked: nil, onConsole: true)
        XCTAssertTrue(state.lockedOrSessionUnavailable, "A missing sample cannot erase a known lock.")
        state.observeSystem(locked: false, onConsole: true)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }

    func testInactiveSessionNotificationIsIndependentOfTheConsolePoll() {
        var state = PresenceState()
        state.observeSystem(locked: false, onConsole: true)
        state.setSessionInactive(true)
        state.observeSystem(locked: false, onConsole: true)
        state.confirmUserInteraction()
        XCTAssertTrue(state.lockedOrSessionUnavailable)
        state.setSessionInactive(false)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }

    func testOffConsoleSessionCannotBeClearedByUnlockOrUserInteraction() {
        var state = PresenceState()
        state.observeSystem(locked: false, onConsole: false)
        state.receiveLockNotification(locked: false)
        state.confirmUserInteraction()
        XCTAssertTrue(state.lockedOrSessionUnavailable)
        state.observeSystem(locked: false, onConsole: true)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }

    func testDisplaySleepStaysSeparateFromLockAndSessionState() {
        var state = PresenceState()
        state.observeSystem(locked: false, onConsole: true)
        state.setDisplaySleeping(true)
        XCTAssertTrue(state.displaySleeping)
        XCTAssertFalse(state.lockedOrSessionUnavailable, "Display sleep must freeze, not reset a rest as a lock.")
        state.setDisplaySleeping(false)
        XCTAssertFalse(state.displaySleeping)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }

    func testDisplayWakeDoesNotUnlockTheSession() {
        var state = PresenceState()
        state.receiveLockNotification(locked: true)
        state.setDisplaySleeping(true)
        state.setDisplaySleeping(false)
        XCTAssertFalse(state.displaySleeping)
        XCTAssertTrue(state.lockedOrSessionUnavailable)
    }

    func testUnknownInteractionCannotOverrideInactiveSessionOrSleepingDisplays() {
        var state = PresenceState()
        state.setSessionInactive(true)
        state.confirmUserInteraction()
        XCTAssertNil(state.systemLocked)
        state.setSessionInactive(false)
        state.setDisplaySleeping(true)
        state.confirmUserInteraction()
        XCTAssertNil(state.systemLocked)
        state.setDisplaySleeping(false)
        state.confirmUserInteraction()
        XCTAssertEqual(state.systemLocked, false)
        XCTAssertFalse(state.lockedOrSessionUnavailable)
    }
}
