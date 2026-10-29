import Foundation
import XCTest
@testable import PomodoroCore

final class PomodoroEngineTests: XCTestCase {
    private let configuration = PomodoroConfiguration(
        focusDuration: 10,
        shortBreakDuration: 3,
        longBreakDuration: 7,
        roundsBeforeLongBreak: 4
    )

    func testStartsReadyAndPausedTicksDoNothing() {
        var engine = PomodoroEngine(configuration: configuration)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining, 10)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.advance(by: 20), [])
        XCTAssertEqual(engine.remaining, 10)

        engine.start()
        engine.advance(by: 2.25)
        engine.pause()
        XCTAssertEqual(engine.remaining, 7.75)
        XCTAssertEqual(engine.advance(by: 100), [])
        XCTAssertEqual(engine.remaining, 7.75)
        engine.start()
        XCTAssertEqual(engine.advance(by: 7.75), [.shortBreak])
    }

    func testEveryFourthCompletedFocusEarnsALongBreak() {
        var engine = PomodoroEngine(configuration: configuration)
        engine.start()
        for session in 1...8 {
            let expected: PomodoroPhase = session % 4 == 0 ? .longBreak : .shortBreak
            XCTAssertEqual(engine.advance(by: 10), [expected])
            XCTAssertEqual(engine.completedFocusSessions, session)
            XCTAssertEqual(engine.remaining, expected == .longBreak ? 7 : 3)
            XCTAssertEqual(engine.advance(by: engine.remaining), [.focus])
        }
    }

    func testDelayedTicksCarryOvershootAcrossMultiplePhases() {
        var engine = PomodoroEngine(configuration: configuration)
        engine.start()
        XCTAssertEqual(engine.advance(by: 25.5), [.shortBreak, .focus, .shortBreak])
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.completedFocusSessions, 2)
        XCTAssertEqual(engine.remaining, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(engine.advance(by: 0.5), [.focus])
        XCTAssertEqual(engine.remaining, 10)
    }

    func testSkippingFocusDoesNotEarnCreditAndPreservesPausedState() {
        var engine = PomodoroEngine(configuration: configuration)
        engine.skipPhase()
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.remaining, 3)
        XCTAssertEqual(engine.completedFocusSessions, 0)
        XCTAssertFalse(engine.isRunning)
        engine.skipPhase()
        XCTAssertEqual(engine.phase, .focus)

        engine.start()
        engine.advance(by: 8)
        engine.skipPhase()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.completedFocusSessions, 0)
        engine.skipPhase()
        XCTAssertEqual(engine.advance(by: 10), [.shortBreak])
        XCTAssertEqual(engine.completedFocusSessions, 1)
    }

    func testResetAndConfigurationChangeStopTheCurrentRun() {
        var engine = PomodoroEngine(configuration: configuration)
        engine.start()
        engine.advance(by: 15)
        engine.reset()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.completedFocusSessions, 0)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.remaining, 10)

        engine.start()
        engine.advance(by: 4)
        let replacement = PomodoroConfiguration(focusDuration: 20, roundsBeforeLongBreak: 2)
        engine.updateConfiguration(replacement)
        XCTAssertEqual(engine.configuration, replacement)
        XCTAssertEqual(engine.remaining, 20)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.completedFocusSessions, 0)
    }

    func testConfigurationClampsDurationsAndRoundCount() throws {
        let normalized = PomodoroConfiguration(
            focusDuration: -2,
            shortBreakDuration: 1_000_000,
            longBreakDuration: .nan,
            roundsBeforeLongBreak: 100
        )
        XCTAssertEqual(normalized.focusDuration, 1)
        XCTAssertEqual(normalized.shortBreakDuration, 86_400)
        XCTAssertEqual(normalized.longBreakDuration, 900)
        XCTAssertEqual(normalized.roundsBeforeLongBreak, 12)
        XCTAssertEqual(PomodoroConfiguration(roundsBeforeLongBreak: -1).roundsBeforeLongBreak, 1)
        XCTAssertEqual(PomodoroConfiguration(focusDuration: .infinity).focusDuration, 1_500)

        let data = Data("{\"focusDuration\":0,\"roundsBeforeLongBreak\":0}".utf8)
        let decoded = try JSONDecoder().decode(PomodoroConfiguration.self, from: data)
        XCTAssertEqual(decoded.focusDuration, 1)
        XCTAssertEqual(decoded.roundsBeforeLongBreak, 1)
        XCTAssertEqual(decoded.shortBreakDuration, 300)
        XCTAssertEqual(try JSONDecoder().decode(PomodoroConfiguration.self, from: JSONEncoder().encode(normalized)), normalized)
    }

    func testInvalidElapsedValuesCannotCorruptTimerState() {
        var engine = PomodoroEngine(configuration: configuration)
        engine.start()
        for elapsed in [-1.0, 0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(engine.advance(by: elapsed), [])
            XCTAssertEqual(engine.remaining, 10)
            XCTAssertEqual(engine.completedFocusSessions, 0)
        }
    }

    func testSingleRoundConfigurationAlwaysTakesLongBreak() {
        var engine = PomodoroEngine(configuration: PomodoroConfiguration(
            focusDuration: 2,
            shortBreakDuration: 1,
            longBreakDuration: 4,
            roundsBeforeLongBreak: 1
        ))
        engine.start()
        XCTAssertEqual(engine.advance(by: 2), [.longBreak])
        XCTAssertEqual(engine.remaining, 4)
        XCTAssertEqual(engine.advance(by: 4), [.focus])
    }
}
