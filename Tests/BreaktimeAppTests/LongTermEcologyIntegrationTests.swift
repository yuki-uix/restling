import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class LongTermEcologyIntegrationTests: XCTestCase {
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
        private var restoredModels: [AppModel] = []

        private struct LegacyArchive: Encodable {
            let version = 1
            let profiles: [ForestProfile]
            let activeProfileID: UUID
        }

        init(completedRests: Int, legacy: Bool = false) throws {
            suite = "LongTermEcologyIntegrationTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let clock = Clock()
            self.clock = clock
            var profile = ForestProfile(name: "保留下来的森林")
            for _ in 0..<completedRests {
                XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                                                date: clock.date.addingTimeInterval(-86_400)))
            }
            baseline = profile
            let archiveData: Data
            if legacy {
                archiveData = try JSONEncoder().encode(LegacyArchive(profiles: [profile], activeProfileID: profile.id))
            } else {
                archiveData = try JSONEncoder().encode(ForestArchive(profiles: [profile],
                    activeProfileID: profile.id, recordingStartedAt: clock.date))
            }
            defaults.set(archiveData, forKey: "forestProfiles.v1")
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                         forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(idlePauseEnabled: false,
                returnGraceSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)),
                         forKey: "reminderPreferences.v1")
            model = AppModel(defaults: defaults, now: { clock.date }, startsTicker: false)
        }

        func restore() -> AppModel {
            let clock = self.clock
            let restored = AppModel(defaults: defaults, now: { clock.date }, startsTicker: false)
            restoredModels.append(restored)
            return restored
        }

        func restID() throws -> UUID {
            let data = try XCTUnwrap(defaults.data(forKey: "reminderSession.v1"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rest = try XCTUnwrap(object["rest"] as? [String: Any])
            return try XCTUnwrap(UUID(uuidString: XCTUnwrap(rest["id"] as? String)))
        }

        func completeOneRest() throws -> UUID {
            model.nextPhase()
            let id = try restID()
            clock.advance(5)
            model.advanceTimer(by: 5)
            return id
        }

        func cleanup() {
            model.stop()
            restoredModels.forEach { $0.stop() }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @MainActor
    func testOnlyNaturalCompletionAtEachThresholdCreatesOneDiscoveryRewardAndOneEvent() async throws {
        for milestone in ForestEcologyMilestone.allCases {
            let f = try Fixture(completedRests: milestone.unlockAfter - 1)
            defer { f.cleanup() }
            let oldTrees = f.baseline.trees
            let seed = f.baseline.seed
            XCTAssertNil(f.model.forest.latestRestReward)
            f.model.nextPhase()
            let id = try f.restID()
            f.clock.advance(4)
            f.model.advanceTimer(by: 4)
            XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(milestone))
            XCTAssertNil(f.model.forest.latestRestReward)
            XCTAssertTrue(f.model.forest.events.isEmpty)

            f.clock.advance(1)
            f.model.advanceTimer(by: 1)
            let current = f.model.forest.current
            let reward = try XCTUnwrap(f.model.forest.latestRestReward)
            XCTAssertEqual(current.completedRests, milestone.unlockAfter)
            XCTAssertEqual(Array(current.trees.dropLast()), oldTrees)
            XCTAssertEqual(current.seed, seed)
            XCTAssertEqual(current.trees.last?.id, id)
            XCTAssertEqual(reward.id, id)
            XCTAssertEqual(reward.profileID, f.baseline.id)
            XCTAssertEqual(reward.completedRests, milestone.unlockAfter)
            XCTAssertTrue(reward.detail.contains(milestone == .visitors ? "兔子" : milestone.title))
            XCTAssertTrue(reward.detail.contains("第 \(milestone.groveIndex + 1) 片"))
            XCTAssertEqual(ForestEcology.milestone(at: reward.completedRests), milestone)
            XCTAssertTrue(ForestEcology(profile: current).isUnlocked(milestone))
            XCTAssertEqual(f.model.forest.events.map(\.id), [id])
            XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed])
            XCTAssertFalse(f.model.forest.completeRest(profileID: current.id, id: id, seconds: 5,
                                                     date: f.clock.date))
            f.model.refreshEligibility()
            f.model.advanceTimer(by: 0)
            XCTAssertEqual(f.model.forest.current, current)
            XCTAssertEqual(f.model.forest.events.count, 1)
            XCTAssertEqual(f.model.forest.latestRestReward?.id, reward.id)
        }
    }

    @MainActor
    func testPreviewSkipAndSnoozeDoNotUnlockAPondWithoutACompletedRest() async throws {
        for action in ["preview", "skip", "snooze"] {
            let f = try Fixture(completedRests: 35)
            defer { f.cleanup() }
            switch action {
            case "preview":
                f.model.preview()
                f.clock.advance(20)
                f.model.advanceTimer(by: 20)
                XCTAssertTrue(f.model.forest.events.isEmpty)
            case "skip":
                f.model.nextPhase()
                f.clock.advance(2)
                f.model.advanceTimer(by: 2)
                f.model.dismissRest()
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
            default:
                f.model.nextPhase()
                f.clock.advance(2)
                f.model.advanceTimer(by: 2)
                f.model.snooze(minutes: 3)
                f.clock.advance(180)
                f.model.refreshEligibility()
                XCTAssertTrue(f.model.showingRest)
                XCTAssertEqual(f.model.engine.remaining, 5)
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
            }
            XCTAssertEqual(f.model.forest.current, f.baseline)
            XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(.pond))
            XCTAssertNil(f.model.forest.latestRestReward)
        }
    }

    @MainActor
    func testLegacy120RestForestDerivesThreeDiscoveriesWithoutFabricatingEventsOrRewards() async throws {
        let f = try Fixture(completedRests: 120, legacy: true)
        defer { f.cleanup() }
        XCTAssertEqual(f.model.forest.current, f.baseline)
        XCTAssertEqual(ForestEcology(profile: f.model.forest.current).unlockedMilestones,
                       [.pond, .bridge, .visitors])
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertNil(f.model.forest.latestRestReward)
        XCTAssertNotNil(f.defaults.data(forKey: "forestProfiles.v1.legacyV1Backup"))
        f.model.refreshEligibility()
        f.model.stop()
        let restored = f.restore()
        XCTAssertEqual(restored.forest.current, f.baseline)
        XCTAssertEqual(ForestEcology(profile: restored.forest.current).unlockedMilestones,
                       [.pond, .bridge, .visitors])
        XCTAssertTrue(restored.forest.events.isEmpty)
        XCTAssertNil(restored.forest.latestRestReward)
    }

    @MainActor
    func testChangingProfilesDuringARestKeepsEcologyAndItsRewardWithTheOriginalForest() async throws {
        let f = try Fixture(completedRests: 35)
        defer { f.cleanup() }
        f.model.nextPhase()
        let id = try f.restID()
        f.model.forest.createProfile(name: "另一片空地")
        let other = f.model.forest.current
        f.clock.advance(5)
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current, other)
        XCTAssertTrue(ForestEcology(profile: other).unlockedMilestones.isEmpty)
        XCTAssertEqual(f.model.forest.latestRestReward?.profileID, f.baseline.id)
        XCTAssertEqual(f.model.forest.events.first?.id, id)
        XCTAssertEqual(f.model.forest.events.first?.profileID, f.baseline.id)
        f.model.forest.selectProfile(f.baseline.id)
        XCTAssertEqual(ForestEcology(profile: f.model.forest.current).unlockedMilestones, [.pond])
        XCTAssertEqual(f.model.forest.current.completedRests, 36)
        f.model.forest.selectProfile(other.id)
        _ = try f.completeOneRest()
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertTrue(ForestEcology(profile: f.model.forest.current).unlockedMilestones.isEmpty)
        XCTAssertEqual(f.model.forest.profiles.first(where: { $0.id == f.baseline.id })?.completedRests, 36)
    }

    @MainActor
    func testSelectingEachNewTreeMidCycleKeepsProgressAndPreviouslyPlantedTrees() async throws {
        for species in [ForestSpecies.birch, .willow, .ginkgo] {
            let f = try Fixture(completedRests: species.unlockAfter + 1)
            defer { f.cleanup() }
            let before = f.model.forest.current
            f.model.forest.selectSpecies(species)
            XCTAssertEqual(f.model.forest.current.growthStage, 1)
            XCTAssertEqual(f.model.forest.current.completedRests, before.completedRests)
            XCTAssertEqual(f.model.forest.current.trees, before.trees)
            XCTAssertEqual(f.model.forest.current.seed, before.seed)
            _ = try f.completeOneRest()
            XCTAssertEqual(f.model.forest.current.growthStage, 2)
            XCTAssertEqual(f.model.forest.current.trees, before.trees)
            _ = try f.completeOneRest()
            XCTAssertEqual(f.model.forest.current.growthStage, 0)
            XCTAssertEqual(Array(f.model.forest.current.trees.dropLast()), before.trees)
            XCTAssertEqual(f.model.forest.current.trees.last?.species, species)
            XCTAssertEqual(f.model.forest.current.seed, before.seed)
            XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed, .completed])
        }
    }

    @MainActor
    func testNewSpeciesBackupRestoreInstallsDataWithoutRewardOrReusingTheOldLiveRest() async throws {
        for species in [ForestSpecies.birch, .willow, .ginkgo] {
            let f = try Fixture(completedRests: species.unlockAfter)
            defer { f.cleanup() }
            f.model.forest.selectSpecies(species)
            for _ in 0..<3 { _ = try f.completeOneRest() }
            let backup = try RestlingBackup.decode(f.model.makeBackup().encoded())
            XCTAssertEqual(backup.forest.profiles[0].trees.last?.species, species)
            XCTAssertEqual(backup.forest.profiles[0].seed, f.baseline.seed)
            f.model.nextPhase()
            let cancelledID = try f.restID()
            try f.model.restoreBackup(backup)
            XCTAssertEqual(try f.model.forest.snapshot(), backup.forest)
            XCTAssertNil(f.model.forest.latestRestReward)
            XCTAssertFalse(f.model.wantsRunning)
            XCTAssertFalse(f.model.engine.isRunning)
            XCTAssertEqual(f.model.engine.phase, .focus)
            f.clock.advance(86_400)
            f.model.advanceTimer(by: 86_400)
            XCTAssertEqual(try f.model.forest.snapshot(), backup.forest)
            XCTAssertNil(f.model.forest.latestRestReward)
            let newID = try f.completeOneRest()
            XCTAssertNotEqual(newID, cancelledID)
            XCTAssertFalse(f.model.forest.events.contains { $0.id == cancelledID })
            XCTAssertEqual(f.model.forest.events.count, backup.forest.events.count + 1)
        }
    }

    @MainActor
    func testPauseSleepAndRelaunchRetainOneRestIdentityWithoutAnEarlyDiscovery() async throws {
        let f = try Fixture(completedRests: 35)
        defer { f.cleanup() }
        f.model.nextPhase()
        let id = try f.restID()
        f.clock.advance(2)
        f.model.advanceTimer(by: 2)
        f.model.toggleRunning()
        let remaining = f.model.engine.remaining
        f.model.willSleep()
        f.clock.advance(86_400)
        f.model.advanceTimer(by: 86_400)
        f.model.didWake()
        f.model.stop()
        XCTAssertEqual(try f.restID(), id)
        XCTAssertEqual(f.model.forest.current, f.baseline)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(.pond))
        let restored = f.restore()
        XCTAssertEqual(restored.engine.phase, .shortBreak)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        XCTAssertFalse(restored.wantsRunning)
        XCTAssertNil(restored.forest.latestRestReward)
        restored.toggleRunning()
        f.clock.advance(remaining)
        restored.advanceTimer(by: remaining)
        XCTAssertEqual(restored.forest.events.map(\.id), [id])
        XCTAssertEqual(restored.forest.events.map(\.outcome), [.completed])
        XCTAssertEqual(restored.forest.current.completedRests, 36)
        XCTAssertTrue(ForestEcology(profile: restored.forest.current).isUnlocked(.pond))
    }

    @MainActor
    func testLongAbsencesAndClockChangesNeitherUnlockFutureEcologyNorRemoveEarlierDiscoveries() async throws {
        let f = try Fixture(completedRests: 119)
        defer { f.cleanup() }
        let baseline = f.model.forest.current
        f.model.toggleRunning()
        f.model.advanceTimer(by: 12)
        f.clock.advance(365 * 86_400)
        f.model.processLiveTick(elapsed: 365 * 86_400)
        f.model.willSleep()
        f.clock.advance(-500 * 86_400)
        f.model.didWake()
        f.model.stop()
        f.clock.advance(700 * 86_400)
        let restored = f.restore()
        XCTAssertEqual(restored.forest.current, baseline)
        XCTAssertEqual(ForestEcology(profile: restored.forest.current).unlockedMilestones, [.pond, .bridge])
        XCTAssertFalse(ForestEcology(profile: restored.forest.current).isUnlocked(.visitors))
        XCTAssertTrue(restored.forest.events.isEmpty)
        XCTAssertNil(restored.forest.latestRestReward)
    }

    @MainActor
    func testLockedTreeSelectionAndPreviewDoNotPlantOrUnlockTheNewTree() async throws {
        let f = try Fixture(completedRests: 35)
        defer { f.cleanup() }
        f.model.forest.selectSpecies(.willow)
        XCTAssertEqual(f.model.forest.current.selectedSpecies, .oak)
        f.model.preview()
        f.clock.advance(20)
        f.model.advanceTimer(by: 20)
        XCTAssertEqual(f.model.forest.current, f.baseline)
        XCTAssertFalse(f.model.forest.current.isUnlocked(.willow))
        _ = try f.completeOneRest()
        XCTAssertTrue(f.model.forest.current.isUnlocked(.willow))
        XCTAssertEqual(f.model.forest.current.selectedSpecies, .oak)
        XCTAssertTrue(f.model.forest.current.trees.allSatisfy { $0.species == .oak })
        let trees = f.model.forest.current.trees
        f.model.forest.selectSpecies(.willow)
        XCTAssertEqual(f.model.forest.current.selectedSpecies, .willow)
        XCTAssertEqual(f.model.forest.current.trees, trees)
        XCTAssertEqual(f.model.forest.events.count, 1)
    }
}
