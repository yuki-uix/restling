import XCTest
@testable import BreaktimeApp

final class AppModelTests: XCTestCase {
    @MainActor
    func testExplicitUpdateHandoffPreservesActiveFocus() async {
        let initial = AppModel()
        let remaining = initial.engine.configuration.focusDuration / 2
        initial.stop()
        let model = AppModel(resumingRemaining: remaining)
        defer { model.stop() }
        XCTAssertEqual(model.engine.phase, .focus)
        XCTAssertEqual(model.engine.remaining, remaining)
        XCTAssertEqual(model.engine.completedFocusSessions, 0)
        XCTAssertTrue(model.engine.isRunning)
        XCTAssertTrue(model.hasStarted)
    }

    @MainActor
    func testHandoffKeepsFourthRoundAndNextLongBreak() async {
        let model = AppModel(resumingRemaining: 1, completedFocusSessions: 3)
        defer { model.stop() }
        XCTAssertEqual(model.currentRound, 4)
        XCTAssertEqual(model.engine.completedFocusSessions, 3)
        var resumed = model.engine
        resumed.advance(by: 1)
        XCTAssertEqual(resumed.phase, .longBreak)
        XCTAssertEqual(resumed.completedFocusSessions, 4)
    }

    @MainActor
    func testHandoffPreservesPausedBreak() async {
        let model = AppModel(resumingRemaining: 1, completedFocusSessions: 2,
                             resumingPhase: .shortBreak, resumeRunning: false)
        defer { model.stop() }
        XCTAssertEqual(model.engine.phase, .shortBreak)
        XCTAssertEqual(model.engine.remaining, 1)
        XCTAssertEqual(model.engine.completedFocusSessions, 2)
        XCTAssertFalse(model.engine.isRunning)
        XCTAssertFalse(model.showingRest)
        model.toggleRunning()
        XCTAssertTrue(model.showingRest)
    }

    @MainActor
    func testSleepingResumesAnActiveSessionWithoutCountingSleep() async {
        let model = AppModel(smokeTest: true)
        defer { model.stop() }
        model.toggleRunning()
        model.willSleep()
        let remaining = model.engine.remaining
        XCTAssertFalse(model.engine.isRunning)
        XCTAssertTrue(model.isSleeping)
        // Duplicate sleep notifications must not erase the resume intent.
        model.willSleep()
        model.didWake()
        XCTAssertTrue(model.engine.isRunning)
        XCTAssertEqual(model.engine.remaining, remaining)
        XCTAssertFalse(model.isSleeping)
    }

    @MainActor
    func testSleepingDoesNotStartAPausedSession() async {
        let model = AppModel(smokeTest: true)
        defer { model.stop() }
        model.willSleep()
        model.didWake()
        XCTAssertFalse(model.engine.isRunning)
        XCTAssertFalse(model.hasStarted)
    }

    @MainActor
    func testClosingPreviewKeepsOriginalPhaseAndPausedState() async {
        let model = AppModel(smokeTest: true)
        defer { model.stop() }
        let original = model.engine.remaining
        model.preview()
        XCTAssertTrue(model.showingRest)
        XCTAssertEqual(model.restRemaining, 20)
        model.dismissRest()
        XCTAssertFalse(model.showingRest)
        XCTAssertEqual(model.engine.phase, .focus)
        XCTAssertEqual(model.engine.remaining, original)
        XCTAssertFalse(model.engine.isRunning)
    }

    @MainActor
    func testEarlyBreakAndEscapeReturnToFocusWithoutEarningCredit() async {
        let model = AppModel(smokeTest: true)
        defer { model.stop() }
        model.nextPhase()
        XCTAssertTrue(model.showingRest)
        XCTAssertEqual(model.engine.phase, .shortBreak)
        XCTAssertTrue(model.engine.isRunning)
        model.dismissRest()
        XCTAssertEqual(model.engine.phase, .focus)
        XCTAssertEqual(model.engine.completedFocusSessions, 0)
        XCTAssertTrue(model.engine.isRunning)
        // A second key event must not accidentally skip the new focus phase.
        model.dismissRest()
        XCTAssertEqual(model.engine.phase, .focus)
    }
}
