import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ForestRewardIntegrationTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (suite: String, defaults: UserDefaults, forest: ForestStore, model: AppModel) {
        let suite = "ForestRewardIntegrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let forest = ForestStore(defaults: defaults)
        let model = AppModel(smokeTest: true, forest: forest)
        model.stop() // Advance the same production path without a live run-loop timer.
        return (suite, defaults, forest, model)
    }

    @MainActor
    func testNaturalBreakCompletionGrantsExactlyOneReward() async throws {
        let f = try fixture()
        defer { f.model.stop(); f.defaults.removePersistentDomain(forName: f.suite) }
        f.model.toggleRunning()
        f.model.advanceTimer(by: 2)
        XCTAssertEqual(f.model.engine.phase, .shortBreak)
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.model.advanceTimer(by: 1)
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.model.advanceTimer(by: 1)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.forest.current.completedRests, 1)
        XCTAssertEqual(f.forest.current.totalRestSeconds, 2)
        for elapsed in [0.0, -1, .nan, .infinity, 0.2, 0.2] {
            f.model.advanceTimer(by: elapsed)
        }
        XCTAssertEqual(f.forest.current.completedRests, 1)
        XCTAssertEqual(ForestStore(defaults: f.defaults).current.completedRests, 1)
    }

    @MainActor
    func testPreviewFreezesRealBreakAndCannotEarnGrowth() async throws {
        let f = try fixture()
        defer { f.model.stop(); f.defaults.removePersistentDomain(forName: f.suite) }
        f.model.nextPhase()
        f.model.preview()
        let originalRemaining = f.model.engine.remaining
        f.model.advanceTimer(by: 30)
        XCTAssertFalse(f.model.isPreview)
        XCTAssertEqual(f.model.engine.phase, .shortBreak)
        XCTAssertEqual(f.model.engine.remaining, originalRemaining)
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.model.dismissRest()
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.forest.current.completedRests, 0)
    }

    @MainActor
    func testSkippedAndResetRestsNeverContributeGrowth() async throws {
        let f = try fixture()
        defer { f.model.stop(); f.defaults.removePersistentDomain(forName: f.suite) }
        f.model.nextPhase()
        f.model.advanceTimer(by: 1)
        f.model.nextPhase()
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.model.nextPhase()
        f.model.advanceTimer(by: 1)
        f.model.reset()
        f.model.advanceTimer(by: 100)
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.model.toggleRunning()
        f.model.advanceTimer(by: 4)
        XCTAssertEqual(f.forest.current.completedRests, 1)
        XCTAssertEqual(f.forest.current.totalRestSeconds, 2)
    }

    @MainActor
    func testSleepTimeIsExcludedAndWakeContinuesTheSameRest() async throws {
        let f = try fixture()
        defer { f.model.stop(); f.defaults.removePersistentDomain(forName: f.suite) }
        f.model.nextPhase()
        f.model.advanceTimer(by: 0.5)
        f.model.willSleep()
        let remaining = f.model.engine.remaining
        f.model.advanceTimer(by: 3_600)
        XCTAssertEqual(f.model.engine.remaining, remaining)
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.model.didWake()
        XCTAssertTrue(f.model.engine.isRunning)
        f.model.advanceTimer(by: remaining)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.forest.current.completedRests, 1)
        XCTAssertEqual(f.forest.current.totalRestSeconds, 2)
    }

    @MainActor
    func testChangingProfileDuringBreakKeepsRewardWithOriginalForest() async throws {
        let f = try fixture()
        defer { f.model.stop(); f.defaults.removePersistentDomain(forName: f.suite) }
        let originalID = f.forest.current.id
        f.model.nextPhase()
        f.forest.createProfile(name: "另一片森林")
        let secondID = f.forest.current.id
        XCTAssertEqual(f.model.restForestProfile.id, originalID)
        f.model.preview()
        XCTAssertEqual(f.model.restForestProfile.id, secondID)
        f.model.dismissRest()
        XCTAssertEqual(f.model.restForestProfile.id, originalID)
        f.model.advanceTimer(by: 2)
        XCTAssertEqual(f.forest.current.id, secondID)
        XCTAssertEqual(f.forest.current.completedRests, 0)
        f.forest.selectProfile(originalID)
        XCTAssertEqual(f.forest.current.completedRests, 1)
        XCTAssertEqual(f.forest.current.totalRestSeconds, 2)
    }

    @MainActor
    func testOneDelayedTickCreditsShortAndLongBreaksWithTheirOwnDurations() async throws {
        let f = try fixture()
        defer { f.model.stop(); f.defaults.removePersistentDomain(forName: f.suite) }
        f.model.toggleRunning()
        // 2 focus + 2 short + 2 focus + 3 long + 2 focus + 2 short.
        f.model.advanceTimer(by: 13)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.completedFocusSessions, 3)
        XCTAssertEqual(f.forest.current.completedRests, 3)
        XCTAssertEqual(f.forest.current.totalRestSeconds, 7)
        XCTAssertEqual(f.forest.current.trees.count, 1)
    }

    @MainActor
    func testResumedBreakCapturesOriginalProfileBeforeItIsSwitched() async throws {
        let suite = "ForestRewardIntegrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let forest = ForestStore(defaults: defaults)
        let originalID = forest.current.id
        let model = AppModel(resumingRemaining: 1, resumingPhase: .shortBreak,
                             resumeRunning: false, forest: forest)
        model.stop()
        defer { model.stop(); defaults.removePersistentDomain(forName: suite) }
        let duration = model.engine.configuration.shortBreakDuration
        forest.createProfile(name: "切换后的森林")
        model.toggleRunning()
        model.advanceTimer(by: 1)
        XCTAssertEqual(forest.current.completedRests, 0)
        forest.selectProfile(originalID)
        XCTAssertEqual(forest.current.completedRests, 1)
        XCTAssertEqual(forest.current.totalRestSeconds, duration)
    }
}
