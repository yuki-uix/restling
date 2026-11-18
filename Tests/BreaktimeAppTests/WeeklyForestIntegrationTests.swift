import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class WeeklyForestIntegrationTests: XCTestCase {
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
        let oldProfile: ForestProfile?
        let originalArchive: Data?
        private var restoredModels: [AppModel] = []

        init(date: Date, legacyRests: Int? = nil) throws {
            suite = "WeeklyForestIntegrationTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let clock = Clock(date)
            self.clock = clock
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            self.calendar = calendar
            if let legacyRests {
                var profile = ForestProfile(name: "最初的森林")
                var events: [ForestRestEvent] = []
                for number in 0..<legacyRests {
                    let restID = UUID()
                    let oldDate = Date(timeIntervalSince1970: 1_577_872_800).addingTimeInterval(Double(number))
                    XCTAssertTrue(profile.recordRest(id: restID, seconds: 20, date: oldDate, calendar: calendar))
                    events.append(ForestRestEvent(id: restID, profileID: profile.id, occurredAt: oldDate,
                                                  configuredSeconds: 20, outcome: .completed))
                }
                if profile.isUnlocked(.pine) { profile.selectedSpecies = .pine }
                oldProfile = profile
                let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                    events: events, recordingStartedAt: Date(timeIntervalSince1970: 1_577_872_800))
                let data = try JSONEncoder().encode(archive)
                originalArchive = data
                defaults.set(data, forKey: "forestProfiles.v1")
            } else {
                oldProfile = nil
                originalArchive = nil
            }
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                         forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(scheduleEnabled: false, weekdays: [2, 6],
                startMinute: 600, endMinute: 1_020, idlePauseEnabled: false, returnGraceSeconds: 0,
                startSoundEnabled: false, endSoundEnabled: false)), forKey: "reminderPreferences.v1")
            defaults.set("cloudy", forKey: "forestWeatherPreference.v1")
            defaults.set(true, forKey: "restForestOnboarding.v1")
            defaults.set(false, forKey: "appUpdates.v1.automaticChecksEnabled")
            model = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
        }

        @discardableResult
        func completeOneRest() throws -> ForestRestEvent {
            let before = model.forest.events.count
            model.nextPhase()
            XCTAssertTrue(model.showingRest)
            clock.advance(5)
            model.advanceTimer(by: 5)
            XCTAssertFalse(model.showingRest)
            XCTAssertEqual(model.forest.events.count, before + 1)
            let event = try XCTUnwrap(model.forest.events.last)
            XCTAssertEqual(event.outcome, .completed)
            return event
        }

        func restoreModel() -> AppModel {
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

    private func date(_ value: String = "2026-11-16T10:00:00Z") -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @MainActor
    func testProductionStoreStartsWeeklyAndOnlyFirstTreeUsesThreeCompletions() async throws {
        let f = try Fixture(date: date())
        defer { f.cleanup() }
        XCTAssertNotNil(f.model.forest.current.weeklyJourney)
        XCTAssertEqual(try f.model.forest.snapshot().version, 4)
        XCTAssertTrue(f.model.forest.current.weeklyJourney!.weeks.isEmpty)
        for _ in 0..<3 { try f.completeOneRest() }
        let first = f.model.forest.current.trees
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(try XCTUnwrap(f.model.forest.latestRestReward).didGrowTree)
        XCTAssertEqual(f.model.forest.current.growthTarget, 24)
        f.model.forest.selectSpecies(.pine)
        for _ in 0..<23 { try f.completeOneRest() }
        XCTAssertEqual(f.model.forest.current.trees, first)
        XCTAssertFalse(try XCTUnwrap(f.model.forest.latestRestReward).didGrowTree)
        XCTAssertEqual(f.model.forest.current.growthCount, 23)
        let final = try f.completeOneRest()
        XCTAssertEqual(f.model.forest.current.trees.map(\.species), [.oak, .pine])
        XCTAssertEqual(f.model.forest.current.trees.last?.id, final.id)
        XCTAssertEqual(f.model.forest.events.filter { $0.outcome == .completed }.count, 27)
        XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.first?.completedRests, 27)
        XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.first?.totalRestSeconds, 135)
        XCTAssertFalse(f.model.forest.completeRest(profileID: final.profileID, id: final.id,
                                                   seconds: final.configuredSeconds, date: final.occurredAt))
        XCTAssertEqual(f.model.forest.current.trees.count, 2)
    }

    @MainActor
    func testActualRestCrossingMidnightMaturesIntoTheNewWeekAndRetainsPriorSnapshot() async throws {
        let f = try Fixture(date: date("2026-11-22T23:59:48Z"))
        defer { f.cleanup() }
        try f.completeOneRest()
        try f.completeOneRest()
        let prior = try XCTUnwrap(f.model.forest.current.weeklyJourney?.weeks.first)
        XCTAssertEqual(prior.id, "2026-11-16")
        XCTAssertEqual(prior.lastGrowthCount, 2)
        let event = try f.completeOneRest()
        let weeks = try XCTUnwrap(f.model.forest.current.weeklyJourney).weeks
        XCTAssertEqual(weeks.map(\.id), ["2026-11-16", "2026-11-23"])
        XCTAssertEqual(weeks.first, prior)
        XCTAssertEqual(weeks.last?.completedRests, 1)
        XCTAssertEqual(weeks.last?.treeIDs, [event.id])
        XCTAssertEqual(f.model.forest.currentWeek?.id, "2026-11-23")
        XCTAssertTrue(try XCTUnwrap(f.model.forest.latestRestReward).startedNewWeek)
        XCTAssertEqual(f.model.forest.current.growthTarget, 24)
        XCTAssertEqual(f.model.forest.current.growthCount, 0)
    }

    @MainActor
    func testPausedWeekRefreshShowsEmptyLandWithoutWritingYearbookOrAwardingGrowth() async throws {
        let f = try Fixture(date: date())
        defer { f.cleanup() }
        try f.completeOneRest()
        f.model.toggleRunning()
        XCTAssertFalse(f.model.wantsRunning)
        let before = try f.model.forest.snapshot()
        let stored = try XCTUnwrap(f.defaults.data(forKey: "forestProfiles.v1"))
        f.clock.date = date("2026-12-07T10:00:00Z")
        f.model.refreshEligibility()
        XCTAssertEqual(f.model.forest.currentWeek?.id, "2026-12-07")
        XCTAssertTrue(try XCTUnwrap(f.model.forest.currentWeek).isEmpty)
        XCTAssertFalse(f.model.engine.isRunning)
        XCTAssertFalse(f.model.wantsRunning)
        XCTAssertEqual(try f.model.forest.snapshot(), before)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), stored)
        try f.completeOneRest()
        XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.map(\.id), ["2026-11-16", "2026-12-07"])
    }

    @MainActor
    func testLegacyMigrationRetainsOriginalTreesEventsAndPreferencesWithoutCreatingHistoricalWeeks() async throws {
        let f = try Fixture(date: date(), legacyRests: 35)
        defer { f.cleanup() }
        let old = try XCTUnwrap(f.oldProfile)
        let current = f.model.forest.current
        let journey = try XCTUnwrap(current.weeklyJourney)
        XCTAssertEqual(current.id, old.id)
        XCTAssertEqual(current.name, old.name)
        XCTAssertEqual(current.seed, old.seed)
        XCTAssertEqual(current.trees, old.trees)
        XCTAssertEqual(current.selectedSpecies, old.selectedSpecies)
        XCTAssertEqual(current.completedRests, 35)
        XCTAssertEqual(current.totalRestSeconds, 700)
        XCTAssertEqual(current.legacyTrees, old.trees)
        XCTAssertEqual(journey.legacySelectedSpecies, .pine)
        XCTAssertTrue(journey.weeks.isEmpty)
        XCTAssertEqual(f.model.forest.events.count, 35)
        XCTAssertTrue(f.model.forest.events.allSatisfy { $0.occurredAt < f.clock.date })
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.legacyV2Backup"), f.originalArchive)
        XCTAssertEqual(f.model.eyeRestSettings, EyeRestSettings(intervalMinutes: 1, restSeconds: 5))
        XCTAssertEqual(f.model.reminderPreferences.weekdays, [2, 6])
        XCTAssertFalse(f.model.reminderPreferences.scheduleEnabled)
        XCTAssertEqual(f.defaults.string(forKey: "forestWeatherPreference.v1"), "cloudy")
        XCTAssertFalse(f.defaults.bool(forKey: "appUpdates.v1.automaticChecksEnabled"))
        XCTAssertEqual(try f.model.forest.snapshot().version, 4)
        let restored = f.restoreModel()
        XCTAssertEqual(restored.forest.current, current)
        XCTAssertEqual(restored.forest.events, f.model.forest.events)
        XCTAssertTrue(restored.forest.current.weeklyJourney!.weeks.isEmpty)
    }

    @MainActor
    func testMigratedSaplingCompletesOnceThenUsesTheSlowCycle() async throws {
        let f = try Fixture(date: date(), legacyRests: 5)
        defer { f.cleanup() }
        let oldTrees = f.model.forest.current.trees
        XCTAssertEqual(f.model.forest.current.growthCount, 2)
        XCTAssertEqual(f.model.forest.current.growthTarget, 3)
        let event = try f.completeOneRest()
        XCTAssertEqual(Array(f.model.forest.current.trees.dropLast()), oldTrees)
        XCTAssertEqual(f.model.forest.current.trees.last?.id, event.id)
        XCTAssertEqual(f.model.forest.current.trees.last?.species, .pine)
        XCTAssertEqual(f.model.forest.current.growthTarget, 24)
        for _ in 0..<23 { try f.completeOneRest() }
        XCTAssertEqual(f.model.forest.current.trees.count, 2)
        XCTAssertEqual(f.model.forest.current.growthCount, 23)
        try f.completeOneRest()
        XCTAssertEqual(f.model.forest.current.trees.count, 3)
        XCTAssertEqual(f.model.forest.current.legacyTrees, oldTrees)
    }

    @MainActor
    func testLayoutPersistsButNeverCreatesEventsRewardsOrEditableHistory() async throws {
        let f = try Fixture(date: date())
        defer { f.cleanup() }
        for _ in 0..<3 { try f.completeOneRest() }
        let id = try XCTUnwrap(f.model.forest.current.trees.first?.id)
        let rewardID = f.model.forest.latestRestReward?.id
        let events = f.model.forest.events
        let trees = f.model.forest.current.trees
        XCTAssertTrue(f.model.forest.moveTree(id: id, to: 15))
        XCTAssertEqual(f.model.forest.currentWeek?.slot(for: id), 15)
        XCTAssertEqual(f.model.forest.events, events)
        XCTAssertEqual(f.model.forest.current.trees, trees)
        XCTAssertEqual(f.model.forest.latestRestReward?.id, rewardID)
        XCTAssertEqual(f.restoreModel().forest.currentWeek?.slot(for: id), 15)
        f.clock.date = date("2026-11-23T10:00:00Z")
        f.model.refreshEligibility()
        let before = try f.model.forest.snapshot()
        XCTAssertFalse(f.model.forest.moveTree(id: id, to: 2))
        XCTAssertEqual(try f.model.forest.snapshot(), before)
        XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.first?.slot(for: id), 15)
    }

    @MainActor
    func testBackupRoundTripKeepsWeeklyHistoryLayoutsAndIsolationFromCancelledTimer() async throws {
        let f = try Fixture(date: date(), legacyRests: 2)
        defer { f.cleanup() }
        try f.completeOneRest()
        let treeID = try XCTUnwrap(f.model.forest.current.trees.first?.id)
        XCTAssertTrue(f.model.forest.moveTree(id: treeID, to: 14))
        f.clock.date = date("2026-11-23T10:00:00Z")
        f.model.refreshEligibility()
        try f.completeOneRest()
        let backup = try RestlingBackup.decode(f.model.makeBackup().encoded())
        XCTAssertEqual(backup.forest.version, 4)
        let original = backup.forest
        f.model.nextPhase()
        XCTAssertTrue(f.model.showingRest)
        f.model.advanceTimer(by: 2)
        try f.model.restoreBackup(backup)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertFalse(f.model.engine.isRunning)
        XCTAssertFalse(f.model.wantsRunning)
        XCTAssertEqual(try f.model.forest.snapshot(), original)
        XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.first?.slot(for: treeID), 14)
        XCTAssertEqual(f.model.forest.current.weeklyJourney?.weeks.count, 2)
        XCTAssertNil(f.model.forest.latestRestReward)
        f.clock.advance(1_000)
        f.model.advanceTimer(by: 1_000)
        XCTAssertEqual(try f.model.forest.snapshot(), original)
        let restored = f.restoreModel()
        XCTAssertEqual(try restored.forest.snapshot(), original)
        XCTAssertEqual(restored.eyeRestSettings, backup.settings.eyeRest)
        XCTAssertEqual(restored.reminderPreferences, backup.settings.reminders)
        XCTAssertFalse(restored.wantsRunning)
    }

    @MainActor
    func testWeekRecordsRemainWithTheRestOwnerWhenSwitchingForestDuringTheTimer() async throws {
        let f = try Fixture(date: date())
        defer { f.cleanup() }
        let ownerID = f.model.forest.current.id
        f.model.nextPhase()
        f.model.forest.createProfile(name: "另一片森林")
        let other = f.model.forest.current
        f.clock.advance(5)
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.id, other.id)
        XCTAssertTrue(f.model.forest.current.weeklyJourney!.weeks.isEmpty)
        let owner = try XCTUnwrap(f.model.forest.profiles.first { $0.id == ownerID })
        XCTAssertEqual(owner.weeklyJourney?.weeks.first?.completedRests, 1)
        XCTAssertEqual(f.model.forest.events.last?.profileID, ownerID)
        f.model.forest.selectProfile(ownerID)
        XCTAssertEqual(f.model.forest.currentWeek?.completedRests, 1)
        f.model.forest.selectProfile(other.id)
        XCTAssertTrue(try XCTUnwrap(f.model.forest.currentWeek).isEmpty)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testPreviewSkipAndSnoozeCannotCreateANewWeeklyForest() async throws {
        for action in ["preview", "skip", "snooze"] {
            let f = try Fixture(date: date())
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
                XCTAssertEqual(f.model.forest.events.map(\.outcome), [.skipped])
            }
            XCTAssertEqual(f.model.forest.current.completedRests, 0)
            XCTAssertTrue(f.model.forest.current.trees.isEmpty)
            XCTAssertTrue(f.model.forest.current.weeklyJourney!.weeks.isEmpty)
            XCTAssertNil(f.model.forest.latestRestReward)
        }
    }
}
