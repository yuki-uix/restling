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
        let legacyBaseline: ForestProfile
        let baseline: ForestProfile
        let baselineEvents: [ForestRestEvent]
        let calendar: Calendar
        let model: AppModel
        private var restoredModels: [AppModel] = []

        private struct LegacyArchive: Encodable {
            let version = 1
            let profiles: [ForestProfile]
            let activeProfileID: UUID
        }

        init(completedRests: Int, legacy: Bool = false, recordedWeeks: Int = 0) throws {
            suite = "LongTermEcologyIntegrationTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let clock = Clock()
            self.clock = clock
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
            var profile = ForestProfile(name: "保留下来的森林")
            for _ in 0..<completedRests {
                XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                                                date: clock.date.addingTimeInterval(-86_400)))
            }
            legacyBaseline = profile
            var seededEvents: [ForestRestEvent] = []
            if recordedWeeks > 0 {
                precondition(!legacy, "A version 1 fixture must remain a true legacy profile")
                let start = clock.date.addingTimeInterval(-Double(recordedWeeks * 14) * 86_400)
                XCTAssertTrue(profile.enableWeeklyGrowth(at: start, calendar: calendar))
                for index in 0..<recordedWeeks {
                    let date = start.addingTimeInterval(Double(index * 14) * 86_400)
                    let id = UUID()
                    XCTAssertTrue(profile.recordRest(id: id, seconds: 20, date: date, calendar: calendar))
                    seededEvents.append(ForestRestEvent(id: id, profileID: profile.id,
                        occurredAt: date, configuredSeconds: 20, outcome: .completed))
                }
            }
            baselineEvents = seededEvents
            let archiveData: Data
            if legacy {
                archiveData = try JSONEncoder().encode(LegacyArchive(profiles: [profile], activeProfileID: profile.id))
            } else {
                archiveData = try JSONEncoder().encode(ForestArchive(profiles: [profile],
                    activeProfileID: profile.id, events: seededEvents, recordingStartedAt: clock.date))
            }
            defaults.set(archiveData, forKey: "forestProfiles.v1")
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                         forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(idlePauseEnabled: false,
                returnGraceSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)),
                         forKey: "reminderPreferences.v1")
            var expected = profile
            if expected.weeklyJourney == nil {
                XCTAssertTrue(expected.enableWeeklyGrowth(at: clock.date, calendar: calendar))
            }
            baseline = expected
            let model = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
            self.model = model
            XCTAssertEqual(model.forest.current, expected)
            XCTAssertEqual(model.forest.current.legacyTrees, legacyBaseline.trees)
        }

        func restore() -> AppModel {
            let clock = self.clock
            let restored = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
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
    func testOnlyNaturalCompletionInTheRequiredWeekCreatesOneDiscoveryAndOneEvent() async throws {
        for milestone in ForestEcologyMilestone.allCases {
            let f = try Fixture(completedRests: milestone.unlockAfter - 1,
                                recordedWeeks: milestone.weeklyUnlockAfter - 1)
            defer { f.cleanup() }
            let before = f.baseline
            let oldTrees = before.trees
            let seedIDs = f.baselineEvents.map(\.id)
            XCTAssertFalse(ForestEcology(profile: before).isUnlocked(milestone))
            XCTAssertNil(f.model.forest.latestRestReward)
            f.model.nextPhase()
            let id = try f.restID()
            f.clock.advance(4)
            f.model.advanceTimer(by: 4)
            XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(milestone))
            XCTAssertEqual(f.model.forest.current, before)
            XCTAssertNil(f.model.forest.latestRestReward)
            XCTAssertEqual(f.model.forest.events.map(\.id), seedIDs)

            f.clock.advance(1)
            f.model.advanceTimer(by: 1)
            let current = f.model.forest.current
            let reward = try XCTUnwrap(f.model.forest.latestRestReward)
            XCTAssertEqual(current.completedRests, before.completedRests + 1)
            XCTAssertEqual(current.totalRestSeconds, before.totalRestSeconds + 5)
            XCTAssertEqual(current.legacyTrees, f.legacyBaseline.trees)
            XCTAssertEqual(Array(current.trees.prefix(oldTrees.count)), oldTrees)
            XCTAssertEqual(current.trees.count, oldTrees.count + (reward.didGrowTree ? 1 : 0))
            XCTAssertEqual(current.seed, before.seed)
            XCTAssertEqual(reward.id, id)
            XCTAssertEqual(reward.profileID, before.id)
            XCTAssertEqual(reward.completedRests, current.completedRests)
            XCTAssertEqual(reward.newDiscoveries, [milestone])
            XCTAssertTrue(reward.title.contains(milestone.title))
            let week = try XCTUnwrap(current.weeklyJourney?.weeks.last)
            XCTAssertEqual(current.weeklyJourney?.weeks.count, milestone.weeklyUnlockAfter)
            XCTAssertEqual(week.restIDs, [id])
            XCTAssertEqual(week.totalRestSeconds, 5)
            XCTAssertEqual(ForestEcology(profile: current).location(for: milestone), .week(week.id))
            XCTAssertEqual(f.model.forest.events.map(\.id), seedIDs + [id])
            XCTAssertTrue(f.model.forest.events.allSatisfy { $0.outcome == .completed })
            XCTAssertFalse(f.model.forest.completeRest(profileID: current.id, id: id, seconds: 5,
                                                     date: f.clock.date))
            f.model.refreshEligibility()
            f.model.advanceTimer(by: 0)
            XCTAssertEqual(f.model.forest.current, current)
            XCTAssertEqual(f.model.forest.events.count, seedIDs.count + 1)
            XCTAssertEqual(f.model.forest.latestRestReward?.id, id)
        }
    }

    @MainActor
    func testPreviewSkipAndSnoozeDoNotUnlockAPondWithoutACompletedRest() async throws {
        for action in ["preview", "skip", "snooze"] {
            let f = try Fixture(completedRests: 35, recordedWeeks: 2)
            defer { f.cleanup() }
            switch action {
            case "preview":
                f.model.preview()
                f.clock.advance(20)
                f.model.advanceTimer(by: 20)
                XCTAssertEqual(f.model.forest.events, f.baselineEvents)
            case "skip":
                f.model.nextPhase()
                f.clock.advance(2)
                f.model.advanceTimer(by: 2)
                f.model.dismissRest()
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed, .completed, .skipped])
            default:
                f.model.nextPhase()
                f.clock.advance(2)
                f.model.advanceTimer(by: 2)
                f.model.snooze(minutes: 3)
                f.clock.advance(180)
                f.model.refreshEligibility()
                XCTAssertTrue(f.model.showingRest)
                XCTAssertEqual(f.model.engine.remaining, 5)
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.completed, .completed, .skipped])
            }
            XCTAssertEqual(f.model.forest.current, f.baseline)
            XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(.pond))
            XCTAssertNil(f.model.forest.latestRestReward)
            XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.count, 2)
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
        let f = try Fixture(completedRests: 35, recordedWeeks: 2)
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
        XCTAssertEqual(f.model.forest.events.last?.id, id)
        XCTAssertEqual(f.model.forest.events.last?.profileID, f.baseline.id)
        f.model.forest.selectProfile(f.baseline.id)
        XCTAssertEqual(ForestEcology(profile: f.model.forest.current).unlockedMilestones, [.pond])
        XCTAssertEqual(f.model.forest.current.completedRests, f.baseline.completedRests + 1)
        f.model.forest.selectProfile(other.id)
        _ = try f.completeOneRest()
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertTrue(ForestEcology(profile: f.model.forest.current).unlockedMilestones.isEmpty)
        XCTAssertEqual(f.model.forest.profiles.first(where: { $0.id == f.baseline.id })?.completedRests, f.baseline.completedRests + 1)
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
            XCTAssertEqual(f.model.forest.current.growthTarget, 24)
            let firstMature = f.model.forest.current.trees
            for _ in 0..<23 { _ = try f.completeOneRest() }
            XCTAssertEqual(f.model.forest.current.trees, firstMature)
            XCTAssertEqual(f.model.forest.current.growthCount, 23)
            _ = try f.completeOneRest()
            XCTAssertEqual(Array(f.model.forest.current.trees.dropLast()), firstMature)
            XCTAssertEqual(f.model.forest.current.trees.last?.species, species)
            XCTAssertEqual(f.model.forest.current.growthCount, 0)
            XCTAssertEqual(f.model.forest.events.count, 26)
            XCTAssertTrue(f.model.forest.events.allSatisfy { $0.outcome == .completed })
        }
    }

    @MainActor
    func testNewSpeciesBackupRestoreInstallsDataWithoutRewardOrReusingTheOldLiveRest() async throws {
        for species in [ForestSpecies.birch, .willow, .ginkgo] {
            let f = try Fixture(completedRests: species.unlockAfter)
            defer { f.cleanup() }
            f.model.forest.selectSpecies(species)
            for _ in 0..<24 { _ = try f.completeOneRest() }
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
        let f = try Fixture(completedRests: 35, recordedWeeks: 2)
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
        XCTAssertEqual(f.model.forest.events, f.baselineEvents)
        XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(.pond))
        let restored = f.restore()
        XCTAssertEqual(restored.engine.phase, .shortBreak)
        XCTAssertEqual(restored.engine.remaining, remaining, accuracy: 0.001)
        XCTAssertFalse(restored.wantsRunning)
        XCTAssertNil(restored.forest.latestRestReward)
        restored.toggleRunning()
        f.clock.advance(remaining)
        restored.advanceTimer(by: remaining)
        XCTAssertEqual(restored.forest.events.map(\.id), f.baselineEvents.map(\.id) + [id])
        XCTAssertTrue(restored.forest.events.allSatisfy { $0.outcome == .completed })
        XCTAssertEqual(restored.forest.current.completedRests, f.baseline.completedRests + 1)
        XCTAssertTrue(ForestEcology(profile: restored.forest.current).isUnlocked(.pond))
        XCTAssertEqual(restored.forest.current.weeklyJourney?.weeks.count, 3)
        XCTAssertEqual(restored.forest.current.weeklyJourney?.weeks.last?.restIDs, [id])
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
        XCTAssertFalse(ForestEcology(profile: f.model.forest.current).isUnlocked(.pond))
        XCTAssertEqual(f.model.forest.current.selectedSpecies, .oak)
        XCTAssertTrue(f.model.forest.current.trees.allSatisfy { $0.species == .oak })
        let trees = f.model.forest.current.trees
        f.model.forest.selectSpecies(.willow)
        XCTAssertEqual(f.model.forest.current.selectedSpecies, .willow)
        XCTAssertEqual(f.model.forest.current.trees, trees)
        XCTAssertEqual(f.model.forest.events.count, 1)
    }
}
