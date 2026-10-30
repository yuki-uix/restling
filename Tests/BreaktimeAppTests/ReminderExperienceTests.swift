import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ReminderExperienceTests: XCTestCase {
    @MainActor
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let clock: Clock
        let calendar: Calendar
        let model: AppModel
        private var restoredModels: [AppModel] = []

        init(preferences: ReminderPreferences, date: Date) throws {
            let suite = "ReminderExperienceTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let clock = Clock(date)
            self.suite = suite
            self.defaults = defaults
            self.clock = clock
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                         forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(preferences), forKey: "reminderPreferences.v1")
            model = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
        }

        func restore() -> AppModel {
            let clock = self.clock
            let restored = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
            restoredModels.append(restored)
            return restored
        }

        func cleanup() {
            model.stop()
            restoredModels.forEach { $0.stop() }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func date(day: Int = 2, hour: Int = 10, minute: Int = 0, second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                                  hour: hour, minute: minute, second: second))!
    }

    @MainActor
    private func fixture(preferences: ReminderPreferences = ReminderPreferences(
        idlePauseEnabled: false, returnGraceSeconds: 0), date initialDate: Date? = nil) throws -> Fixture {
        try Fixture(preferences: preferences, date: initialDate ?? date())
    }

    @MainActor
    func testPrewarningThresholdDismissalAndFreshCycle() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 49)
        XCTAssertFalse(f.model.isPrewarningVisible)
        f.model.advanceTimer(by: 1)
        XCTAssertTrue(f.model.isPrewarningVisible)
        f.model.refreshEligibility()
        XCTAssertTrue(f.model.isPrewarningVisible)
        f.model.dismissPrewarning()
        f.model.advanceTimer(by: 9)
        XCTAssertFalse(f.model.isPrewarningVisible)
        f.model.advanceTimer(by: 1)
        XCTAssertTrue(f.model.showingRest)
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        f.model.advanceTimer(by: 50)
        XCTAssertTrue(f.model.isPrewarningVisible)
    }

    @MainActor
    func testRepeatedThreeThenFiveMinuteSnoozeHasOneDeadlineAndOneBreak() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 3)
        XCTAssertTrue(f.model.isSnoozing)
        XCTAssertFalse(f.model.isPrewarningVisible)
        XCTAssertEqual(f.model.displayedRemaining, 180, accuracy: 0.001)
        f.clock.advance(1)
        f.model.snooze(minutes: 5)
        XCTAssertEqual(f.model.displayedRemaining, 300, accuracy: 0.001)
        f.model.advanceTimer(by: 10_000)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        XCTAssertFalse(f.model.showingRest)
        f.clock.advance(299)
        f.model.refreshEligibility()
        XCTAssertTrue(f.model.isSnoozing)
        f.clock.advance(1)
        f.model.refreshEligibility()
        f.model.refreshEligibility()
        XCTAssertFalse(f.model.isSnoozing)
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.model.restRemaining, 5, accuracy: 0.001)
        XCTAssertEqual(cues, [.start])
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertEqual(cues, [.start, .end])
    }

    @MainActor
    func testSnoozingAnActiveRestCancelsItsPartialReward() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        f.model.snooze(minutes: 3)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        f.clock.advance(180)
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.restRemaining, 5, accuracy: 0.001)
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertEqual(f.model.forest.current.totalRestSeconds, 5)
    }

    @MainActor
    func testSnoozeRequiresAnEligibleReminderAndRejectsUnsupportedMinutes() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.snooze(minutes: 5)
        XCTAssertFalse(f.model.isSnoozing)
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 1)
        XCTAssertFalse(f.model.isSnoozing)
        f.model.pauseFor(minutes: 30)
        f.model.snooze(minutes: 3)
        XCTAssertFalse(f.model.isSnoozing)
        XCTAssertFalse(f.model.isPrewarningVisible)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testWorkWindowEndSuppressesReminderAndNextWindowStartsFresh() async throws {
        let prefs = ReminderPreferences(scheduleEnabled: true, weekdays: [2],
            idlePauseEnabled: false, returnGraceSeconds: 0)
        let f = try fixture(preferences: prefs, date: date(hour: 17, minute: 59, second: 30))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 58)
        XCTAssertTrue(f.model.isPrewarningVisible)
        f.clock.date = date(hour: 18)
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.pauseReason, .outsideSchedule)
        XCTAssertFalse(f.model.isPrewarningVisible)
        XCTAssertFalse(f.model.showingRest)
        f.model.advanceTimer(by: 100_000)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        XCTAssertTrue(cues.isEmpty)
        f.clock.date = date(day: 9, hour: 9)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.pauseReason)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertTrue(cues.isEmpty)
        f.model.advanceTimer(by: 60)
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(cues, [.start])
    }

    @MainActor
    func testStartingOutsideSelectedDayRemembersIntentWithoutAccumulatedReminder() async throws {
        let prefs = ReminderPreferences(scheduleEnabled: true, weekdays: [2],
            idlePauseEnabled: false, returnGraceSeconds: 0)
        let f = try fixture(preferences: prefs, date: date(day: 1))
        defer { f.cleanup() }
        f.model.toggleRunning()
        XCTAssertTrue(f.model.wantsRunning)
        XCTAssertFalse(f.model.engine.isRunning)
        XCTAssertEqual(f.model.pauseReason, .outsideSchedule)
        f.clock.date = date(hour: 9)
        f.model.refreshEligibility()
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testDoNotDisturbExpiresExactlyOnceAndAdvertisesItsResumeTime() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 20)
        f.model.pauseFor(minutes: 30)
        XCTAssertEqual(f.model.pauseReason, .doNotDisturb)
        XCTAssertTrue(f.model.menuBarTitle.contains("勿扰"))
        XCTAssertTrue(f.model.statusDescription.contains("自动恢复"))
        XCTAssertNotNil(f.model.doNotDisturbUntil)
        f.clock.advance(1_799)
        f.model.refreshEligibility()
        XCTAssertFalse(f.model.engine.isRunning)
        f.clock.advance(1)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.doNotDisturbUntil)
        XCTAssertNil(f.model.pauseReason)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testExpiredDoNotDisturbCannotOverrideOutsideScheduleOrManualPause() async throws {
        let prefs = ReminderPreferences(scheduleEnabled: true, weekdays: [2],
            idlePauseEnabled: false, returnGraceSeconds: 0)
        let f = try fixture(preferences: prefs, date: date(hour: 17, minute: 50))
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.pauseFor(minutes: 30)
        f.clock.advance(1_800)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.doNotDisturbUntil)
        XCTAssertEqual(f.model.pauseReason, .outsideSchedule)
        XCTAssertFalse(f.model.engine.isRunning)
        f.model.toggleRunning()
        XCTAssertFalse(f.model.wantsRunning)
        f.clock.date = date(day: 9, hour: 9)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.pauseReason)
        XCTAssertFalse(f.model.engine.isRunning)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testDoNotDisturbExpiryWaitsForBothSleepAndLockToClear() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.pauseFor(minutes: 30)
        f.model.willSleep()
        f.model.updatePresence(locked: true, idleSeconds: 0)
        f.clock.advance(1_800)
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.pauseReason, .sleeping)
        XCTAssertFalse(f.model.engine.isRunning)
        f.model.didWake()
        XCTAssertEqual(f.model.pauseReason, .locked)
        XCTAssertFalse(f.model.engine.isRunning)
        f.model.updatePresence(locked: false, idleSeconds: 0)
        XCTAssertNil(f.model.pauseReason)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testManualPauseDuringDoNotDisturbPreventsItsAutomaticResume() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.pauseFor(minutes: 60)
        f.model.toggleRunning()
        XCTAssertFalse(f.model.wantsRunning)
        f.clock.advance(3_600)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.pauseReason)
        XCTAssertFalse(f.model.engine.isRunning)
        XCTAssertFalse(f.model.showingRest)
    }

    @MainActor
    func testRunningFocusRestoresItsRemainingTimeAfterAnOfflineDayAndGrace() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 20)
        let remaining = f.model.engine.remaining
        f.model.stop()
        f.clock.advance(86_400)
        let restored = f.restore()
        XCTAssertTrue(restored.hasStarted)
        XCTAssertTrue(restored.wantsRunning)
        XCTAssertEqual(restored.pauseReason, .returnGrace)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        restored.advanceTimer(by: 100_000)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
        f.clock.advance(30)
        restored.refreshEligibility()
        XCTAssertNil(restored.pauseReason)
        XCTAssertTrue(restored.engine.isRunning)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        restored.advanceTimer(by: 1)
        XCTAssertEqual(restored.engine.remaining, remaining - 1, accuracy: 0.001)
    }

    @MainActor
    func testManuallyPausedFocusRestoresWithoutStartingOrAddingGrace() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 20)
        f.model.toggleRunning()
        let remaining = f.model.engine.remaining
        f.model.stop()
        f.clock.advance(86_400)
        let restored = f.restore()
        XCTAssertTrue(restored.hasStarted)
        XCTAssertFalse(restored.wantsRunning)
        XCTAssertFalse(restored.engine.isRunning)
        XCTAssertNil(restored.returnGraceUntil)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        restored.advanceTimer(by: 100_000)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
    }

    @MainActor
    func testNeverStartedSessionRemainsReadyAcrossRestart() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.stop()
        let restored = f.restore()
        XCTAssertFalse(restored.hasStarted)
        XCTAssertFalse(restored.wantsRunning)
        XCTAssertFalse(restored.engine.isRunning)
        XCTAssertEqual(restored.engine.remaining, 60)
    }

    @MainActor
    func testPausedBreakSnapshotRestoresWithoutResumingUntilExplicitlyRequested() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        f.model.toggleRunning()
        let remaining = f.model.engine.remaining
        f.model.stop()
        f.clock.advance(86_400)
        let restored = f.restore()
        XCTAssertFalse(restored.wantsRunning)
        XCTAssertFalse(restored.engine.isRunning)
        XCTAssertEqual(restored.engine.phase, .shortBreak)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        XCTAssertNil(restored.returnGraceUntil)
        restored.advanceTimer(by: 100_000)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
        restored.toggleRunning()
        restored.advanceTimer(by: remaining)
        XCTAssertEqual(restored.forest.current.completedRests, 1)
    }

    @MainActor
    func testDoNotDisturbDeadlineSurvivesRestartWithoutCountingOfflineTime() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.pauseFor(minutes: 30)
        let deadline = try XCTUnwrap(f.model.doNotDisturbUntil)
        f.model.stop()
        f.clock.advance(600)
        let restored = f.restore()
        XCTAssertTrue(restored.wantsRunning)
        XCTAssertFalse(restored.engine.isRunning)
        XCTAssertEqual(restored.pauseReason, .doNotDisturb)
        XCTAssertEqual(restored.doNotDisturbUntil, deadline)
        f.clock.advance(1_200)
        restored.refreshEligibility()
        XCTAssertNil(restored.doNotDisturbUntil)
        XCTAssertNil(restored.pauseReason)
        XCTAssertTrue(restored.engine.isRunning)
        XCTAssertEqual(restored.engine.remaining, 60, accuracy: 0.001)
        XCTAssertFalse(restored.showingRest)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
    }

    @MainActor
    func testRestRestoreKeepsOriginalProfileAndStableRewardIDAcrossSnapshotReplay() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        let originalProfile = f.model.forest.current.id
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        f.model.stop()
        let oldSnapshot = try XCTUnwrap(f.defaults.data(forKey: "reminderSession.v1"))
        f.model.forest.createProfile(name: "另一片森林")
        let restored = f.restore()
        XCTAssertEqual(restored.restForestProfile.id, originalProfile)
        XCTAssertNotEqual(restored.forest.current.id, originalProfile)
        XCTAssertEqual(restored.engine.phase, .shortBreak)
        XCTAssertEqual(restored.engine.remaining, 3, accuracy: 0.001)
        restored.advanceTimer(by: 3)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
        restored.forest.selectProfile(originalProfile)
        XCTAssertEqual(restored.forest.current.completedRests, 1)
        restored.stop()

        // Simulate a crash that left the pre-reward timer snapshot behind after
        // the forest ledger had already persisted the completed reward.
        f.defaults.set(oldSnapshot, forKey: "reminderSession.v1")
        let replayed = f.restore()
        var replaySounds: [RestSoundCue] = []
        replayed.onSound = { replaySounds.append($0) }
        replayed.advanceTimer(by: 3)
        XCTAssertEqual(replayed.forest.current.completedRests, 1)
        XCTAssertEqual(replayed.forest.current.totalRestSeconds, 5)
        XCTAssertTrue(replaySounds.isEmpty)
    }

    @MainActor
    func testFiveMinuteSnoozeSurvivesRestartWithOneMinuteFocusConfiguration() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 5)
        f.model.stop()
        f.clock.advance(100)
        let restored = f.restore()
        XCTAssertTrue(restored.isSnoozing)
        XCTAssertEqual(restored.displayedRemaining, 200, accuracy: 0.001)
        XCTAssertEqual(restored.engine.remaining, 60, accuracy: 0.001)
        XCTAssertFalse(restored.showingRest)
        f.clock.advance(200)
        restored.refreshEligibility()
        XCTAssertTrue(restored.showingRest)
        XCTAssertEqual(restored.restRemaining, 5, accuracy: 0.001)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
    }

    @MainActor
    func testExpiredSnoozeAtRestartStartsFreshInsteadOfReplayingAnOfflineBreak() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 5)
        f.model.stop()
        f.clock.advance(600)
        let restored = f.restore()
        XCTAssertFalse(restored.isSnoozing)
        XCTAssertFalse(restored.showingRest)
        XCTAssertEqual(restored.engine.phase, .focus)
        XCTAssertEqual(restored.engine.remaining, 60, accuracy: 0.001)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
    }

    @MainActor
    func testLockCancelsPartialRestAndUnlockProvidesReturnGrace() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        cues.removeAll()
        f.model.updatePresence(locked: true, idleSeconds: 0)
        XCTAssertEqual(f.model.pauseReason, .locked)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        f.clock.advance(86_400)
        f.model.updatePresence(locked: false, idleSeconds: 0)
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        XCTAssertFalse(f.model.engine.isRunning)
        f.model.advanceTimer(by: 1_000)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        f.clock.advance(29)
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        f.clock.advance(1)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.pauseReason)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertTrue(cues.isEmpty)
    }

    @MainActor
    func testRemainingStillDuringRestDoesNotRequireInputToEarnItsReward() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: true,
            idleThresholdSeconds: 60, returnGraceSeconds: 0))
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.updatePresence(locked: false, idleSeconds: 600)
        XCTAssertFalse(f.model.isIdle)
        XCTAssertTrue(f.model.showingRest)
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        f.model.updatePresence(locked: false, idleSeconds: 600)
        XCTAssertTrue(f.model.isIdle)
        XCTAssertEqual(f.model.pauseReason, .idle)
        XCTAssertFalse(f.model.engine.isRunning)
        f.model.updatePresence(locked: false, idleSeconds: 0)
        XCTAssertFalse(f.model.isIdle)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
    }

    @MainActor
    func testRepeatedPresenceSamplesDoNotExtendReturnGrace() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.updatePresence(locked: true, idleSeconds: 0)
        f.model.updatePresence(locked: true, idleSeconds: 0)
        f.model.updatePresence(locked: false, idleSeconds: 0)
        let deadline = try XCTUnwrap(f.model.returnGraceUntil)
        f.clock.advance(20)
        f.model.updatePresence(locked: false, idleSeconds: 0)
        XCTAssertEqual(f.model.returnGraceUntil, deadline)
        f.clock.advance(10)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.returnGraceUntil)
        XCTAssertTrue(f.model.engine.isRunning)
    }

    @MainActor
    func testSleepFreezesSameRestAndWakeGraceDoesNotEarnAnOfflineReward() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        let remaining = f.model.engine.remaining
        f.model.willSleep()
        f.model.willSleep()
        f.clock.advance(86_400)
        f.model.advanceTimer(by: 86_400)
        XCTAssertEqual(f.model.engine.remaining, remaining, accuracy: 0.001)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        f.model.didWake()
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        XCTAssertEqual(f.model.engine.phase, .shortBreak)
        f.clock.advance(30)
        f.model.refreshEligibility()
        f.model.advanceTimer(by: remaining)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertEqual(f.model.forest.current.totalRestSeconds, 5)
    }

    @MainActor
    func testSoundChoicesPersistAndStartEndCanBeControlledIndependently() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 0,
            startSoundEnabled: false, endSoundEnabled: true))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.nextPhase()
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(cues, [.end])
        var prefs = f.model.reminderPreferences
        prefs.startSoundEnabled = true
        prefs.endSoundEnabled = false
        f.model.applyReminderPreferences(prefs)
        cues.removeAll()
        f.model.nextPhase()
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(cues, [.start])
        f.model.stop()
        let restored = f.restore()
        XCTAssertTrue(restored.reminderPreferences.startSoundEnabled)
        XCTAssertFalse(restored.reminderPreferences.endSoundEnabled)
    }

    @MainActor
    func testPreviewSkippingAndDoNotDisturbDoNotPlayCompletionSounds() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.preview()
        f.model.advanceTimer(by: 20)
        XCTAssertTrue(cues.isEmpty)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        f.model.nextPhase()
        XCTAssertEqual(cues, [.start])
        cues.removeAll()
        f.model.dismissRest()
        XCTAssertTrue(cues.isEmpty)
        f.model.pauseFor(minutes: 30)
        f.clock.advance(1_800)
        f.model.refreshEligibility()
        f.model.refreshEligibility()
        XCTAssertTrue(cues.isEmpty)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testScheduleClosingDuringRestCancelsItsRewardAndEndSound() async throws {
        let prefs = ReminderPreferences(scheduleEnabled: true, weekdays: [2],
            idlePauseEnabled: false, returnGraceSeconds: 0)
        let f = try fixture(preferences: prefs, date: date(hour: 17, minute: 59, second: 59))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        cues.removeAll()
        f.clock.advance(1)
        f.model.refreshEligibility()
        f.model.advanceTimer(by: 100)
        XCTAssertEqual(f.model.pauseReason, .outsideSchedule)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        XCTAssertTrue(cues.isEmpty)
    }

    @MainActor
    func testDisplaySleepAndSystemSleepFreezeTheSameRestWithoutBecomingLock() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: true,
            idleThresholdSeconds: 60, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        let remaining = f.model.engine.remaining
        f.model.updatePresence(locked: false, idleSeconds: 600, displaySleeping: true)
        XCTAssertEqual(f.model.pauseReason, .displaySleeping)
        XCTAssertFalse(f.model.isIdle)
        f.model.willSleep()
        f.clock.advance(3_600)
        f.model.advanceTimer(by: 3_600)
        f.model.didWake()
        XCTAssertEqual(f.model.pauseReason, .displaySleeping)
        f.model.updatePresence(locked: false, idleSeconds: 0, displaySleeping: false)
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        XCTAssertEqual(f.model.engine.phase, .shortBreak)
        XCTAssertEqual(f.model.engine.remaining, remaining, accuracy: 0.001)
        f.clock.advance(30)
        f.model.refreshEligibility()
        f.model.advanceTimer(by: remaining)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertEqual(f.model.forest.current.totalRestSeconds, 5)
    }

    @MainActor
    func testDelayedLiveFocusTickPresentsAFullBreakBeforeAnyReward() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 59)
        f.model.processLiveTick(elapsed: 20)
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.model.restRemaining, 5, accuracy: 0.001)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        f.model.processLiveTick(elapsed: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
    }

    @MainActor
    func testSuspendedProcessDoesNotReplayUnseenBreaks() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.processLiveTick(elapsed: 86_400)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testDelayedLivePreviewNeverChangesTheUnderlyingSession() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 20)
        let remaining = f.model.engine.remaining
        f.model.preview()
        f.model.processLiveTick(elapsed: 100)
        XCTAssertFalse(f.model.isPreview)
        XCTAssertEqual(f.model.engine.remaining, remaining, accuracy: 0.01)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testSuspendedProcessDiscardsAnOverdueSnoozeBeforeReturnGraceEnds() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 5)
        f.clock.advance(86_400)
        f.model.processLiveTick(elapsed: 86_400)
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        XCTAssertNil(f.model.snoozeUntil)
        f.clock.advance(30)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.pauseReason)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertTrue(cues.isEmpty)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testSnoozeExpiringDuringSystemSleepDoesNotBecomeAnOverdueBreakAfterWake() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 5)
        f.model.willSleep()
        f.clock.advance(600)
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.pauseReason, .sleeping)
        f.model.didWake()
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        f.clock.advance(30)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.snoozeUntil)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertTrue(cues.isEmpty)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testSnoozeExpiringDuringDisplaySleepStartsFreshAfterDisplayReturns() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 5)
        f.model.updatePresence(locked: false, idleSeconds: 0, displaySleeping: true)
        f.clock.advance(600)
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.pauseReason, .displaySleeping)
        f.model.updatePresence(locked: false, idleSeconds: 0, displaySleeping: false)
        XCTAssertEqual(f.model.pauseReason, .returnGrace)
        f.clock.advance(30)
        f.model.refreshEligibility()
        XCTAssertNil(f.model.snoozeUntil)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.remaining, 60, accuracy: 0.001)
        XCTAssertTrue(f.model.engine.isRunning)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertTrue(cues.isEmpty)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testUnexpiredSnoozeKeepsItsDeadlineThroughSystemOrDisplaySleep() async throws {
        for displayOnly in [false, true] {
            let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 30))
            defer { f.cleanup() }
            f.model.toggleRunning()
            f.model.advanceTimer(by: 50)
            f.model.snooze(minutes: 5)
            let deadline = try XCTUnwrap(f.model.snoozeUntil)
            f.clock.advance(120)
            if displayOnly {
                f.model.updatePresence(locked: false, idleSeconds: 0, displaySleeping: true)
            } else {
                f.model.willSleep()
            }
            f.clock.advance(60)
            if displayOnly {
                f.model.updatePresence(locked: false, idleSeconds: 0, displaySleeping: false)
            } else {
                f.model.didWake()
            }
            XCTAssertEqual(f.model.pauseReason, .returnGrace)
            XCTAssertEqual(f.model.snoozeUntil, deadline)
            f.clock.advance(30)
            f.model.refreshEligibility()
            XCTAssertNil(f.model.pauseReason)
            XCTAssertTrue(f.model.isSnoozing)
            XCTAssertEqual(f.model.displayedRemaining, 90, accuracy: 0.001)
            XCTAssertFalse(f.model.engine.isRunning)
            XCTAssertFalse(f.model.showingRest)
            f.clock.advance(90)
            f.model.refreshEligibility()
            XCTAssertTrue(f.model.showingRest)
            XCTAssertEqual(f.model.restRemaining, 5, accuracy: 0.001)
            XCTAssertEqual(f.model.forest.current.completedRests, 0)
        }
    }

    @MainActor
    func testRestNowAtSnoozeDeadlineDoesNotImmediatelySkipTheNewBreak() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        var cues: [RestSoundCue] = []
        f.model.onSound = { cues.append($0) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 50)
        f.model.snooze(minutes: 3)
        // The wall-clock deadline has passed, but the next timer callback has
        // not yet reconciled it. The visible menu action still means Rest Now.
        f.clock.advance(180)
        f.model.nextPhase()
        XCTAssertNil(f.model.snoozeUntil)
        XCTAssertEqual(f.model.engine.phase, .shortBreak)
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.model.restRemaining, 5, accuracy: 0.001)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        XCTAssertEqual(cues, [.start])
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertEqual(cues, [.start, .end])
    }

}
