import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ForestAchievementsIntegrationTests: XCTestCase {
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

        private struct LegacyArchive: Encodable {
            let version = 1
            let profiles: [ForestProfile]
            let activeProfileID: UUID
        }

        init(completedRests: Int, legacy: Bool = false) throws {
            suite = "ForestAchievementsIntegrationTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let clock = Clock()
            self.clock = clock
            var profile = ForestProfile(name: "保留已有足迹")
            for _ in 0..<completedRests {
                XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                    date: clock.date.addingTimeInterval(-86_400)))
            }
            baseline = profile
            let data: Data
            if legacy {
                data = try JSONEncoder().encode(LegacyArchive(profiles: [profile], activeProfileID: profile.id))
            } else {
                data = try JSONEncoder().encode(ForestArchive(profiles: [profile],
                    activeProfileID: profile.id, recordingStartedAt: clock.date))
            }
            defaults.set(data, forKey: "forestProfiles.v1")
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(idlePauseEnabled: false,
                returnGraceSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)),
                forKey: "reminderPreferences.v1")
            model = AppModel(defaults: defaults, now: { clock.date }, startsTicker: false)
        }

        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            model.advanceTimer(by: seconds)
        }

        func cleanup() {
            model.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @MainActor
    func testLegacyCumulativeProgressIsRecognizedWithoutInventingEventsOrChangingOldTrees() async throws {
        let f = try Fixture(completedRests: 120, legacy: true)
        defer { f.cleanup() }
        XCTAssertEqual(f.model.forest.current, f.baseline)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertNil(f.model.forest.latestRestReward)
        let saved = try f.model.forest.snapshot()
        let bytes = f.defaults.data(forKey: "forestProfiles.v1")
        let achievements = ForestAchievements(profile: f.model.forest.current)
        XCTAssertTrue(achievements.progress(for: .hundredRests).isUnlocked)
        XCTAssertTrue(achievements.progress(for: .thirdGrove).isUnlocked)
        XCTAssertTrue(achievements.progress(for: .visitors).isUnlocked)
        XCTAssertTrue(achievements.progress(for: .tenMinutes).isUnlocked)
        XCTAssertFalse(achievements.progress(for: .oneHour).isUnlocked)
        XCTAssertFalse(achievements.progress(for: .twoSpecies).isUnlocked)
        for _ in 0..<100 {
            XCTAssertEqual(ForestAchievements(profile: f.model.forest.current), achievements)
        }
        XCTAssertEqual(try f.model.forest.snapshot(), saved)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), bytes)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertNil(f.model.forest.latestRestReward)
    }

    @MainActor
    func testPreviewSkipAndSnoozeDoNotCompleteAnAchievement() async throws {
        for action in ["preview", "skip", "snooze"] {
            let f = try Fixture(completedRests: 2)
            defer { f.cleanup() }
            let before = ForestAchievements(profile: f.baseline)
            switch action {
            case "preview":
                f.model.preview()
                f.advance(20)
                XCTAssertTrue(f.model.forest.events.isEmpty)
            case "skip":
                f.model.nextPhase()
                f.advance(2)
                f.model.dismissRest()
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
            default:
                f.model.nextPhase()
                f.advance(2)
                f.model.snooze(minutes: 3)
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
            }
            XCTAssertEqual(ForestAchievements(profile: f.model.forest.current), before)
            XCTAssertEqual(f.model.forest.current, f.baseline)
            XCTAssertFalse(before.progress(for: .firstTree).isUnlocked)
            XCTAssertNil(f.model.forest.latestRestReward)
        }
    }

    @MainActor
    func testNaturalCompletionUnlocksOnceAndReadingAchievementsNeverAddsAReward() async throws {
        let f = try Fixture(completedRests: 2)
        defer { f.cleanup() }
        XCTAssertFalse(ForestAchievements(profile: f.model.forest.current).progress(for: .firstTree).isUnlocked)
        f.model.nextPhase()
        f.advance(4)
        XCTAssertFalse(ForestAchievements(profile: f.model.forest.current).progress(for: .firstTree).isUnlocked)
        f.advance(1)
        let profile = f.model.forest.current
        let event = try XCTUnwrap(f.model.forest.events.first)
        XCTAssertEqual(event.outcome, .completed)
        XCTAssertEqual(profile.completedRests, 3)
        XCTAssertEqual(profile.trees.count, 1)
        XCTAssertEqual(profile.totalRestSeconds, 45)
        let achievements = ForestAchievements(profile: profile)
        XCTAssertTrue(achievements.progress(for: .firstTree).isUnlocked)
        let saved = try f.model.forest.snapshot()
        let rewardID = f.model.forest.latestRestReward?.id
        for _ in 0..<100 { _ = ForestAchievements(profile: f.model.forest.current).nextAchievement }
        XCTAssertFalse(f.model.forest.completeRest(profileID: profile.id, id: event.id, seconds: 5, date: f.clock.date))
        f.model.refreshEligibility()
        XCTAssertEqual(try f.model.forest.snapshot(), saved)
        XCTAssertEqual(f.model.forest.events.count, 1)
        XCTAssertEqual(f.model.forest.latestRestReward?.id, rewardID)
        XCTAssertEqual(ForestAchievements(profile: f.model.forest.current), achievements)
    }

    @MainActor
    func testAchievementsStayWithTheirForestWhenCreatingAndSwitchingProfiles() async throws {
        let f = try Fixture(completedRests: 49)
        defer { f.cleanup() }
        let oldAchievements = ForestAchievements(profile: f.model.forest.current)
        XCTAssertTrue(oldAchievements.progress(for: .newGrove).isUnlocked)
        f.model.forest.createProfile(name: "另一片空地")
        let newID = f.model.forest.current.id
        XCTAssertEqual(ForestAchievements(profile: f.model.forest.current).unlockedCount, 0)
        f.model.nextPhase()
        f.advance(5)
        let newAchievements = ForestAchievements(profile: f.model.forest.current)
        XCTAssertTrue(newAchievements.progress(for: .firstRest).isUnlocked)
        XCTAssertFalse(newAchievements.progress(for: .firstTree).isUnlocked)
        XCTAssertFalse(newAchievements.progress(for: .newGrove).isUnlocked)
        f.model.forest.selectProfile(f.baseline.id)
        XCTAssertEqual(ForestAchievements(profile: f.model.forest.current), oldAchievements)
        f.model.forest.selectProfile(newID)
        XCTAssertEqual(ForestAchievements(profile: f.model.forest.current), newAchievements)
        XCTAssertEqual(f.model.forest.events.count, 1)
        XCTAssertEqual(f.model.forest.events.first?.profileID, newID)
    }
}
