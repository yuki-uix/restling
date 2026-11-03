import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class RestScreenBreathingIntegrationTests: XCTestCase {
    @MainActor
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_793_613_600)
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let clock: Clock
        let baseline: ForestProfile
        let model: AppModel

        init(restSeconds: Int = 20) throws {
            suite = "RestScreenBreathingIntegrationTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let clock = Clock()
            self.clock = clock
            var profile = ForestProfile(name: "整屏呼吸验收森林")
            // Keep a genuine existing 2/3 tree so one completed rest must create
            // exactly one tree while every presentation-only call preserves it.
            for _ in 0..<2 {
                XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                                                date: clock.date.addingTimeInterval(-60)))
            }
            baseline = profile
            defaults.set(try JSONEncoder().encode(ForestArchive(profiles: [profile],
                activeProfileID: profile.id, recordingStartedAt: clock.date)), forKey: "forestProfiles.v1")
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1,
                restSeconds: restSeconds)), forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(idlePauseEnabled: false,
                returnGraceSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)),
                forKey: "reminderPreferences.v1")
            model = AppModel(defaults: defaults, now: { clock.date }, startsTicker: false)
        }

        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            model.advanceTimer(by: seconds)
        }

        func restID() throws -> UUID {
            let data = try XCTUnwrap(defaults.data(forKey: "reminderSession.v1"))
            let session = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rest = try XCTUnwrap(session["rest"] as? [String: Any])
            return try XCTUnwrap(UUID(uuidString: XCTUnwrap(rest["id"] as? String)))
        }

        func cleanup() {
            model.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @MainActor
    func testRealRestUsesItsEarnedElapsedTimeAndCompletesExactlyOnce() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let restID = try f.restID()
        XCTAssertEqual(f.model.restScreenElapsed, 0)
        for (elapsed, opacity) in [(5.0, 0.12), (10.0, 0.0), (15.0, 0.12)] {
            f.advance(5)
            XCTAssertTrue(f.model.showingRest)
            XCTAssertEqual(f.model.restScreenElapsed, elapsed, accuracy: 1e-9)
            XCTAssertEqual(f.model.restScreenDimming(), opacity, accuracy: 1e-12)
            XCTAssertEqual(f.model.forest.current, f.baseline)
            XCTAssertTrue(f.model.forest.events.isEmpty)
        }
        let storedBeforeDraws = f.defaults.data(forKey: "forestProfiles.v1")
        let remaining = f.model.engine.remaining
        for _ in 0..<100 { _ = f.model.restScreenDimming() }
        XCTAssertEqual(f.model.engine.remaining, remaining)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), storedBeforeDraws)

        f.advance(5)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenElapsed, 0)
        XCTAssertEqual(f.model.restScreenDimming(), 0)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.forest.events.map(\.id), [restID])
        XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed])
        XCTAssertEqual(f.model.forest.events.first?.configuredSeconds, 20)
        XCTAssertEqual(f.model.forest.current.completedRests, f.baseline.completedRests + 1)
        XCTAssertEqual(f.model.forest.current.trees.count, f.baseline.trees.count + 1)
        XCTAssertEqual(f.model.forest.current.trees.last?.id, restID)
        XCTAssertEqual(f.model.forest.latestRestReward?.id, restID)
        let saved = try f.model.forest.snapshot()
        for _ in 0..<100 { _ = f.model.restScreenDimming() }
        f.model.refreshEligibility()
        XCTAssertEqual(try f.model.forest.snapshot(), saved)
        XCTAssertEqual(f.model.forest.events.count, 1)
    }

    @MainActor
    func testPreviewHasItsOwnTwentySecondPhaseWithoutAdvancingTheUnderlyingRest() async throws {
        let f = try Fixture(restSeconds: 5)
        defer { f.cleanup() }
        f.model.nextPhase()
        let originalID = try f.restID()
        f.advance(1)
        f.model.preview()
        let actualRemaining = f.model.engine.remaining
        XCTAssertTrue(f.model.isPreview)
        XCTAssertEqual(f.model.restScreenElapsed, 0)
        XCTAssertEqual(f.model.restRemaining, 20)
        f.advance(5)
        XCTAssertEqual(f.model.restScreenElapsed, 5)
        XCTAssertEqual(f.model.restScreenDimming(), 0.12, accuracy: 1e-12)
        XCTAssertEqual(f.model.engine.remaining, actualRemaining)
        f.advance(15)
        XCTAssertFalse(f.model.isPreview)
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.model.engine.remaining, actualRemaining)
        XCTAssertEqual(f.model.restScreenElapsed, 5 - actualRemaining, accuracy: 1e-9)
        XCTAssertEqual(f.model.forest.current, f.baseline)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertNil(f.model.forest.latestRestReward)
        f.advance(actualRemaining)
        XCTAssertEqual(f.model.forest.events.map(\.id), [originalID])
        XCTAssertEqual(f.model.forest.events.first?.configuredSeconds, 5)
        XCTAssertEqual(f.model.forest.current.completedRests, f.baseline.completedRests + 1)
    }

    @MainActor
    func testPauseAndSleepFreezeThePhaseRatherThanCountingOfflineTime() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let restID = try f.restID()
        f.advance(5)
        f.model.toggleRunning()
        let elapsedWhenPaused = f.model.restScreenElapsed
        let remainingWhenPaused = f.model.engine.remaining
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenDimming(), 0)
        f.advance(3_600)
        XCTAssertEqual(f.model.restScreenElapsed, elapsedWhenPaused)
        XCTAssertEqual(f.model.engine.remaining, remainingWhenPaused)
        f.model.toggleRunning()
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenElapsed, elapsedWhenPaused)
        XCTAssertEqual(f.model.restScreenDimming(),
                       RestScreenBreathing.opacity(at: elapsedWhenPaused), accuracy: 1e-12)

        f.model.willSleep()
        let elapsedWhenSleeping = f.model.restScreenElapsed
        let remainingWhenSleeping = f.model.engine.remaining
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenDimming(), 0)
        f.advance(86_400)
        XCTAssertEqual(f.model.restScreenElapsed, elapsedWhenSleeping)
        XCTAssertEqual(f.model.engine.remaining, remainingWhenSleeping)
        f.model.didWake()
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenElapsed, elapsedWhenSleeping)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertEqual(f.model.forest.current, f.baseline)
        f.advance(remainingWhenSleeping)
        XCTAssertEqual(f.model.forest.events.map(\.id), [restID])
        XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed])
    }

    @MainActor
    func testLockHidesDimmingAndPreservesTheExistingFreshIntervalPolicy() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        let restID = try f.restID()
        f.advance(5)
        f.model.updatePresence(locked: true, idleSeconds: 0)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenDimming(), 0)
        XCTAssertEqual(f.model.restScreenElapsed, 0)
        XCTAssertEqual(f.model.engine.phase, .focus)
        f.advance(86_400)
        f.model.updatePresence(locked: false, idleSeconds: 0)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.remaining, 60)
        XCTAssertEqual(f.model.restScreenDimming(), 0)
        XCTAssertEqual(f.model.forest.events.map(\.id), [restID])
        XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
        XCTAssertEqual(f.model.forest.current, f.baseline)
        XCTAssertNil(f.model.forest.latestRestReward)
    }

    @MainActor
    func testFiveSecondCustomRestEndsAtItsOwnDeadlineWithoutWaitingForTheCycle() async throws {
        let f = try Fixture(restSeconds: 5)
        defer { f.cleanup() }
        f.model.nextPhase()
        f.advance(4.5)
        XCTAssertTrue(f.model.showingRest)
        XCTAssertGreaterThan(f.model.restScreenDimming(), 0)
        f.advance(0.5)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.restScreenDimming(), 0)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.forest.events.count, 1)
        XCTAssertEqual(f.model.forest.events.first?.configuredSeconds, 5)
        XCTAssertEqual(f.model.forest.events.first?.outcome, .completed)
        XCTAssertEqual(f.model.forest.current.completedRests, f.baseline.completedRests + 1)
    }

    @MainActor
    func testReduceMotionOnlyChangesPresentationAndNeverTimerOrGrowth() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.model.nextPhase()
        f.advance(5)
        let remaining = f.model.engine.remaining
        let saved = try f.model.forest.snapshot()
        for _ in 0..<20 {
            XCTAssertEqual(f.model.restScreenDimming(reduceMotion: true), 0)
            XCTAssertEqual(f.model.restScreenDimming(), 0.12, accuracy: 1e-12)
        }
        XCTAssertEqual(f.model.engine.remaining, remaining)
        XCTAssertEqual(f.model.restScreenElapsed, 5)
        XCTAssertEqual(try f.model.forest.snapshot(), saved)
        XCTAssertNil(f.model.forest.latestRestReward)
        f.advance(remaining)
        XCTAssertEqual(f.model.forest.events.count, 1)
        XCTAssertEqual(f.model.forest.events.first?.outcome, .completed)
        XCTAssertEqual(f.model.forest.current.completedRests, f.baseline.completedRests + 1)
    }

    @MainActor
    func testSkipAndEitherSnoozeHideImmediatelyWithoutGrowth() async throws {
        for minutes in [0, 3, 5] {
            let f = try Fixture()
            defer { f.cleanup() }
            f.model.nextPhase()
            let restID = try f.restID()
            f.advance(5)
            if minutes == 0 { f.model.dismissRest() }
            else { f.model.snooze(minutes: minutes) }
            XCTAssertFalse(f.model.showingRest)
            XCTAssertEqual(f.model.restScreenDimming(), 0)
            XCTAssertEqual(f.model.restScreenElapsed, 0)
            XCTAssertEqual(f.model.isSnoozing, minutes > 0)
            XCTAssertEqual(f.model.forest.events.map(\.id), [restID])
            XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
            XCTAssertEqual(f.model.forest.current, f.baseline)
            XCTAssertNil(f.model.forest.latestRestReward)
            f.advance(10)
            XCTAssertFalse(f.model.showingRest)
            XCTAssertEqual(f.model.restScreenDimming(), 0)
            XCTAssertEqual(f.model.forest.events.count, 1)
            XCTAssertEqual(f.model.forest.current, f.baseline)
        }
    }
}
