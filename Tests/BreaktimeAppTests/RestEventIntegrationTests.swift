import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class RestEventIntegrationTests: XCTestCase {
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
            suite = "RestEventIntegrationTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            clock = Clock(date)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                         forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(preferences), forKey: "reminderPreferences.v1")
            let clock = self.clock
            let forest = ForestStore(defaults: defaults, now: { clock.date })
            model = AppModel(forest: forest, defaults: defaults, now: { clock.date },
                             calendar: calendar, startsTicker: false)
        }

        func restoredModel() -> AppModel {
            let clock = self.clock
            let forest = ForestStore(defaults: defaults, now: { clock.date })
            let restored = AppModel(forest: forest, defaults: defaults, now: { clock.date },
                                    calendar: calendar, startsTicker: false)
            restoredModels.append(restored)
            return restored
        }

        func savedRestID() throws -> UUID {
            let data = try XCTUnwrap(defaults.data(forKey: "reminderSession.v1"))
            let session = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rest = try XCTUnwrap(session["rest"] as? [String: Any])
            return try XCTUnwrap(UUID(uuidString: XCTUnwrap(rest["id"] as? String)))
        }

        func cleanup() {
            model.stop()
            restoredModels.forEach { $0.stop() }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func date(hour: Int = 10, minute: Int = 0, second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 2,
                                                  hour: hour, minute: minute, second: second))!
    }

    @MainActor
    private func fixture(preferences: ReminderPreferences = ReminderPreferences(
        idlePauseEnabled: false, returnGraceSeconds: 0), date: Date? = nil) throws -> Fixture {
        try Fixture(preferences: preferences, date: date ?? self.date())
    }

    @MainActor
    private func assertOneSkip(_ f: Fixture, originalID: UUID, ownerID: UUID,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let events = f.model.forest.events
        XCTAssertEqual(events.count, 1, file: file, line: line)
        let event = try XCTUnwrap(events.first, file: file, line: line)
        XCTAssertEqual(event.id, originalID, file: file, line: line)
        XCTAssertEqual(event.profileID, ownerID, file: file, line: line)
        XCTAssertEqual(event.outcome, .skipped, file: file, line: line)
        XCTAssertEqual(event.configuredSeconds, 5, file: file, line: line)
        XCTAssertEqual(event.occurredAt, f.clock.date, file: file, line: line)
        XCTAssertTrue(f.model.forest.profiles.allSatisfy { $0.completedRests == 0 && $0.totalRestSeconds == 0 },
                      file: file, line: line)
        XCTAssertEqual(ForestStore(defaults: f.defaults).events, events, file: file, line: line)
    }

    @MainActor
    func testNaturalCompletionRecordsConfiguredDurationTerminalTimeAndOriginalForestOnce() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        let ownerID = f.model.forest.current.id
        f.model.toggleRunning()
        f.clock.advance(60)
        f.model.advanceTimer(by: 60)
        // Ticks throttle their session snapshot. Force the same save used at
        // normal quit before inspecting the newly started rest's persisted ID.
        f.model.stop()
        let restID = try f.savedRestID()
        XCTAssertTrue(f.model.forest.events.isEmpty)
        f.model.forest.createProfile(name: "后来切换的森林")
        let otherID = f.model.forest.current.id
        f.clock.advance(5)
        f.model.advanceTimer(by: 5)
        let event = try XCTUnwrap(f.model.forest.events.first)
        XCTAssertEqual(f.model.forest.events.count, 1)
        XCTAssertEqual(event.id, restID)
        XCTAssertEqual(event.profileID, ownerID)
        XCTAssertEqual(event.configuredSeconds, 5)
        XCTAssertEqual(event.occurredAt, f.clock.date)
        XCTAssertEqual(event.outcome, .completed)
        XCTAssertEqual(f.model.forest.current.id, otherID)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        XCTAssertEqual(f.model.forest.profiles.first(where: { $0.id == ownerID })?.completedRests, 1)
        XCTAssertEqual(ForestStore(defaults: f.defaults).events, [event])
        f.model.refreshEligibility()
        f.model.advanceTimer(by: 0)
        XCTAssertEqual(f.model.forest.events, [event])
    }

    @MainActor
    func testManualSkipKeepsOriginalForestAndCannotTurnIntoASecondTerminalRecord() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        let ownerID = f.model.forest.current.id
        f.model.nextPhase()
        let restID = try f.savedRestID()
        f.model.advanceTimer(by: 2)
        f.model.forest.createProfile(name: "另一片")
        f.clock.advance(2)
        f.model.nextPhase()
        try assertOneSkip(f, originalID: restID, ownerID: ownerID)
        XCTAssertFalse(f.model.forest.completeRest(profileID: ownerID, id: restID, seconds: 5, date: f.clock.date))
        XCTAssertFalse(f.model.forest.skipRest(profileID: ownerID, id: restID, seconds: 5, date: f.clock.date))
        XCTAssertEqual(f.model.forest.events.count, 1)
    }

    @MainActor
    func testSnoozingPartialRestRecordsOneSkipAndPrewarningSnoozeRecordsNothing() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        let ownerID = f.model.forest.current.id
        f.model.nextPhase()
        let restID = try f.savedRestID()
        f.model.advanceTimer(by: 1)
        f.clock.advance(1)
        f.model.snooze(minutes: 3)
        try assertOneSkip(f, originalID: restID, ownerID: ownerID)
        f.model.snooze(minutes: 5)
        XCTAssertEqual(f.model.forest.events.count, 1)

        let beforeRest = try fixture()
        defer { beforeRest.cleanup() }
        beforeRest.model.toggleRunning()
        beforeRest.model.advanceTimer(by: 50)
        XCTAssertTrue(beforeRest.model.isPrewarningVisible)
        beforeRest.model.snooze(minutes: 3)
        XCTAssertTrue(beforeRest.model.forest.events.isEmpty)
        XCTAssertEqual(beforeRest.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testResetRhythmAndLegacyConfigurationChangesEachTerminateOneRealAttempt() async throws {
        for action in ["reset", "rhythm", "legacy"] {
            let f = try fixture()
            defer { f.cleanup() }
            let ownerID = f.model.forest.current.id
            f.model.nextPhase()
            let restID = try f.savedRestID()
            f.model.advanceTimer(by: 2)
            f.clock.advance(2)
            switch action {
            case "reset": f.model.reset(); f.model.reset()
            case "rhythm":
                f.model.applyEyeRestSettings(EyeRestSettings(intervalMinutes: 20, restSeconds: 30))
            default:
                f.model.apply(PomodoroConfiguration(focusDuration: 120, shortBreakDuration: 15,
                    longBreakDuration: 15, roundsBeforeLongBreak: 4))
            }
            try assertOneSkip(f, originalID: restID, ownerID: ownerID)
            f.model.refreshEligibility()
            XCTAssertEqual(f.model.forest.events.count, 1)
        }
    }

    @MainActor
    func testLockDoNotDisturbAndLongProcessStallCancelOnlyTheExistingAttempt() async throws {
        for reason in ["lock", "doNotDisturb", "processStall"] {
            let f = try fixture()
            defer { f.cleanup() }
            let ownerID = f.model.forest.current.id
            f.model.nextPhase()
            let restID = try f.savedRestID()
            f.model.advanceTimer(by: 1)
            f.clock.advance(1)
            switch reason {
            case "lock":
                f.model.updatePresence(locked: true, idleSeconds: 0)
                f.model.updatePresence(locked: true, idleSeconds: 0)
            case "doNotDisturb":
                f.model.pauseFor(minutes: 30)
                f.model.pauseFor(minutes: 60)
            default:
                f.clock.advance(86_400)
                f.model.processLiveTick(elapsed: 86_400)
                f.model.processLiveTick(elapsed: 86_400)
            }
            try assertOneSkip(f, originalID: restID, ownerID: ownerID)
        }
    }

    @MainActor
    func testClosingWorkWindowRecordsOneSkipAtClosureWithoutGrowth() async throws {
        let preferences = ReminderPreferences(scheduleEnabled: true, weekdays: [2], startMinute: 540,
            endMinute: 660, idlePauseEnabled: false, returnGraceSeconds: 0)
        let f = try fixture(preferences: preferences, date: date(hour: 10, minute: 59, second: 58))
        defer { f.cleanup() }
        let ownerID = f.model.forest.current.id
        f.model.nextPhase()
        let restID = try f.savedRestID()
        f.clock.advance(3)
        f.model.refreshEligibility()
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.pauseReason, .outsideSchedule)
        try assertOneSkip(f, originalID: restID, ownerID: ownerID)
    }

    @MainActor
    func testPreviewNeverRecordsAnAttemptAndFreezesAnUnderlyingRealAttempt() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.preview()
        f.clock.advance(20)
        f.model.advanceTimer(by: 20)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        f.model.nextPhase()
        let restID = try f.savedRestID()
        f.model.preview()
        let remaining = f.model.engine.remaining
        f.clock.advance(20)
        f.model.advanceTimer(by: 20)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertEqual(f.model.engine.remaining, remaining)
        f.clock.advance(remaining)
        f.model.advanceTimer(by: remaining)
        XCTAssertEqual(f.model.forest.events.map(\.id), [restID])
        XCTAssertEqual(f.model.forest.events.first?.outcome, .completed)
    }

    @MainActor
    func testPauseSleepAndQuitRetainTheSameAttemptUntilItActuallyFinishes() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let restID = try f.savedRestID()
        f.model.advanceTimer(by: 2)
        f.model.toggleRunning()
        f.clock.advance(60)
        f.model.advanceTimer(by: 60)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        f.model.toggleRunning()
        f.model.willSleep()
        let remaining = f.model.engine.remaining
        f.clock.advance(3_600)
        f.model.advanceTimer(by: 3_600)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertEqual(f.model.engine.remaining, remaining)
        f.model.didWake()
        f.model.stop()
        f.clock.advance(86_400)
        let restored = f.restoredModel()
        XCTAssertTrue(restored.forest.events.isEmpty)
        XCTAssertEqual(restored.engine.remaining, remaining)
        XCTAssertEqual(try f.savedRestID(), restID)
        f.clock.advance(remaining)
        restored.advanceTimer(by: remaining)
        XCTAssertEqual(restored.forest.events.map(\.id), [restID])
        XCTAssertEqual(restored.forest.events.first?.outcome, .completed)
        XCTAssertEqual(restored.forest.events.first?.occurredAt, f.clock.date)
        XCTAssertEqual(restored.forest.current.completedRests, 1)
        restored.stop()
        let again = f.restoredModel()
        XCTAssertEqual(again.forest.events, restored.forest.events)
        XCTAssertEqual(again.forest.current.completedRests, 1)
    }

    @MainActor
    func testStillnessDuringRealRestDoesNotCreateASkippedEvent() async throws {
        let f = try fixture(preferences: ReminderPreferences(idlePauseEnabled: true,
            idleThresholdSeconds: 60, returnGraceSeconds: 0))
        defer { f.cleanup() }
        f.model.nextPhase()
        f.model.updatePresence(locked: false, idleSeconds: 3_600)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertTrue(f.model.showingRest)
        f.clock.advance(5)
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed])
    }

    @MainActor
    func testReplayingPreviouslyCompletedTimerSnapshotCannotAddAnotherEventOrReward() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let beforeCompletion = try XCTUnwrap(f.defaults.data(forKey: "reminderSession.v1"))
        let restID = try f.savedRestID()
        f.clock.advance(5)
        f.model.advanceTimer(by: 5)
        f.model.stop()
        let completed = f.model.forest.events
        f.defaults.set(beforeCompletion, forKey: "reminderSession.v1")
        let replay = f.restoredModel()
        XCTAssertEqual(replay.engine.phase, .focus)
        XCTAssertEqual(replay.engine.remaining, replay.engine.configuration.focusDuration)
        XCTAssertFalse(replay.showingRest)
        XCTAssertEqual(replay.forest.events.map(\.id), [restID])
        replay.advanceTimer(by: 5)
        replay.reset()
        XCTAssertEqual(replay.forest.events, completed)
        XCTAssertEqual(replay.forest.current.completedRests, 1)
    }

    @MainActor
    func testLegacyCreditedTimerSnapshotDoesNotInventADatedHistoricalEvent() async throws {
        struct LegacyArchive: Encodable {
            let version = 1
            let profiles: [ForestProfile]
            let activeProfileID: UUID
        }
        let f = try fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let restID = try f.savedRestID()
        var legacy = f.model.forest.current
        legacy.recordRest(id: restID, seconds: 5, date: f.clock.date)
        f.model.stop()
        f.defaults.set(try JSONEncoder().encode(LegacyArchive(profiles: [legacy], activeProfileID: legacy.id)),
                       forKey: "forestProfiles.v1")
        f.clock.advance(86_400)
        let replay = f.restoredModel()
        XCTAssertEqual(replay.engine.phase, .focus)
        XCTAssertEqual(replay.engine.remaining, replay.engine.configuration.focusDuration)
        XCTAssertFalse(replay.showingRest)
        XCTAssertTrue(replay.forest.events.isEmpty)
        replay.advanceTimer(by: 5)
        XCTAssertTrue(replay.forest.events.isEmpty)
        XCTAssertEqual(replay.forest.current.completedRests, 1)
        XCTAssertEqual(replay.forest.current.totalRestSeconds, 5)
    }

    @MainActor
    func testReplayingPreviouslySkippedTimerSnapshotStartsFreshFocusWithoutShowingOldRest() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let restID = try f.savedRestID()
        let beforeSkip = try XCTUnwrap(f.defaults.data(forKey: "reminderSession.v1"))
        f.model.advanceTimer(by: 1)
        f.clock.advance(1)
        f.model.nextPhase()
        f.model.stop()
        let skipped = f.model.forest.events
        XCTAssertEqual(skipped.map(\.id), [restID])
        XCTAssertEqual(skipped.map(\.outcome), [.skipped])
        f.defaults.set(beforeSkip, forKey: "reminderSession.v1")
        f.clock.advance(86_400)
        let replay = f.restoredModel()
        XCTAssertEqual(replay.engine.phase, .focus)
        XCTAssertEqual(replay.engine.remaining, replay.engine.configuration.focusDuration)
        XCTAssertFalse(replay.showingRest)
        XCTAssertEqual(replay.forest.events, skipped)
        replay.advanceTimer(by: 5)
        XCTAssertEqual(replay.forest.events, skipped)
        XCTAssertEqual(replay.forest.current.completedRests, 0)
        XCTAssertEqual(replay.forest.current.totalRestSeconds, 0)
    }

    @MainActor
    func testLongOfflineGapDoesNotGenerateMissedRestEventsOrConsumeFocusTime() async throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 12)
        f.model.stop()
        let remaining = f.model.engine.remaining
        f.clock.advance(30 * 86_400)
        let restored = f.restoredModel()
        XCTAssertEqual(restored.engine.phase, .focus)
        XCTAssertEqual(restored.engine.remaining, remaining)
        XCTAssertTrue(restored.forest.events.isEmpty)
        XCTAssertEqual(restored.forest.current.completedRests, 0)
    }
}
