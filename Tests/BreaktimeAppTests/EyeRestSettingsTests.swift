import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class EyeRestSettingsTests: XCTestCase {
    @MainActor
    private func isolatedDefaults() throws -> (String, UserDefaults) {
        let suite = "EyeRestSettingsTests." + UUID().uuidString
        return (suite, try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    @MainActor
    func testFreshLaunchUsesTwentyMinutesAndTwentySeconds() async throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        defer { model.stop() }
        XCTAssertEqual(model.eyeRestSettings, EyeRestSettings(intervalMinutes: 20, restSeconds: 20))
        XCTAssertEqual(model.engine.remaining, 1_200)
        XCTAssertEqual(model.engine.configuration.shortBreakDuration, 20)
        XCTAssertEqual(model.engine.configuration.longBreakDuration, 20)
        XCTAssertFalse(model.engine.isRunning)
        XCTAssertFalse(model.hasStarted)
        XCTAssertNotNil(defaults.data(forKey: "eyeRestSettings.v1"))
    }

    @MainActor
    func testLegacyPomodoroSettingsDoNotOverrideEyeRestAndRemainRecoverable() async throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = try JSONEncoder().encode(PomodoroConfiguration())
        defaults.set(legacy, forKey: "pomodoroConfiguration.v1")
        let model = AppModel(defaults: defaults)
        defer { model.stop() }
        XCTAssertEqual(model.engine.configuration.focusDuration, 1_200)
        XCTAssertEqual(model.engine.configuration.shortBreakDuration, 20)
        XCTAssertEqual(defaults.data(forKey: "pomodoroConfiguration.v1"), legacy)
    }

    @MainActor
    func testCustomEyeRestSettingsSurviveRepeatedLaunchesAndMigration() async throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(PomodoroConfiguration()), forKey: "pomodoroConfiguration.v1")
        let model = AppModel(defaults: defaults)
        model.applyEyeRestSettings(EyeRestSettings(intervalMinutes: 30, restSeconds: 40))
        model.stop()
        for _ in 0..<2 {
            let restored = AppModel(defaults: defaults)
            XCTAssertEqual(restored.eyeRestSettings, EyeRestSettings(intervalMinutes: 30, restSeconds: 40))
            XCTAssertEqual(restored.engine.remaining, 1_800)
            XCTAssertEqual(restored.engine.configuration.shortBreakDuration, 40)
            XCTAssertEqual(restored.engine.configuration.longBreakDuration, 40)
            restored.stop()
        }
    }

    @MainActor
    func testEveryReminderUsesTwentySecondsIncludingFourthAndEighth() async throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.stop()
        defer { model.stop() }
        model.toggleRunning()
        for index in 1...8 {
            model.advanceTimer(by: 1_200)
            XCTAssertNotEqual(model.engine.phase, .focus)
            XCTAssertEqual(model.engine.remaining, 20)
            XCTAssertEqual(model.engine.phase.title, "放松眼睛")
            model.advanceTimer(by: 20)
            XCTAssertEqual(model.engine.phase, .focus)
            XCTAssertEqual(model.engine.remaining, 1_200)
            XCTAssertEqual(model.forest.current.completedRests, index)
            XCTAssertEqual(model.forest.current.totalRestSeconds, Double(index * 20))
        }
    }

    @MainActor
    func testChangingEyeRestSettingsResetsTimerAndPreservesEarnedForest() async throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let forest = ForestStore(defaults: defaults)
        for _ in 0..<3 {
            forest.completeRest(profileID: forest.current.id, id: UUID(), seconds: 20)
        }
        let before = forest.current
        let model = AppModel(forest: forest, defaults: defaults)
        model.stop()
        defer { model.stop() }
        model.nextPhase()
        model.advanceTimer(by: 10)
        model.applyEyeRestSettings(EyeRestSettings(intervalMinutes: 15, restSeconds: 30))
        XCTAssertEqual(forest.current, before)
        XCTAssertEqual(model.engine.phase, .focus)
        XCTAssertEqual(model.engine.remaining, 900)
        XCTAssertFalse(model.engine.isRunning)
        XCTAssertFalse(model.hasStarted)
        model.advanceTimer(by: 10_000)
        XCTAssertEqual(forest.current, before)
    }

    func testSettingsNormalizeCreationMutationAndDecodingBoundaries() throws {
        var settings = EyeRestSettings(intervalMinutes: -1, restSeconds: 1_000)
        XCTAssertEqual(settings.intervalMinutes, 1)
        XCTAssertEqual(settings.restSeconds, 180)
        settings.intervalMinutes = 1_000
        settings.restSeconds = -1
        XCTAssertEqual(settings.intervalMinutes, 120)
        XCTAssertEqual(settings.restSeconds, 5)
        XCTAssertEqual(settings.configuration.focusDuration, 7_200)
        XCTAssertEqual(settings.configuration.shortBreakDuration, 5)
        let decoded = try JSONDecoder().decode(EyeRestSettings.self,
            from: Data("{\"intervalMinutes\":0,\"restSeconds\":0}".utf8))
        XCTAssertEqual(decoded, EyeRestSettings(intervalMinutes: 1, restSeconds: 5))
        XCTAssertEqual(try JSONDecoder().decode(EyeRestSettings.self, from: Data("{}".utf8)), EyeRestSettings())
    }
}
