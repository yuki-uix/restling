import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ForestEncounterIntegrationTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let suite = "ForestEncounterIntegrationTests." + UUID().uuidString
        let defaults: UserDefaults
        let calendar: Calendar
        let monday = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00Z")!

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            self.calendar = calendar
        }

        func store(at date: Date? = nil) -> ForestStore {
            let fixedDate = date ?? monday
            return ForestStore(defaults: defaults, now: { fixedDate }, calendar: calendar)
        }

        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }

    @MainActor
    func testNaturalCompletionsPersistOneDailyRollAndNeverAccelerateTreeGrowth() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        var seenEncounters = 0
        for day in 0..<3 {
            for rest in 0..<18 {
                let id = UUID()
                let date = f.monday.addingTimeInterval(Double(day * 86_400 + rest * 1_200))
                XCTAssertTrue(store.completeRest(profileID: store.current.id, id: id, seconds: 20, date: date))
                let week = try XCTUnwrap(store.current.weeklyJourney?.weeks.first)
                XCTAssertEqual(week.encounterRolls?.count, day + 1)
                let encounter = week.encounters.first { $0.id == id }
                XCTAssertEqual(store.latestRestReward?.newEncounter, encounter?.kind)
                if encounter != nil { seenEncounters += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(seenEncounters, 1)
        XCTAssertLessThanOrEqual(seenEncounters, 2)
        XCTAssertEqual(store.current.completedRests, 54)
        XCTAssertEqual(store.current.totalRestSeconds, 1_080)
        XCTAssertEqual(store.current.trees.count, 3)
        XCTAssertEqual(store.current.growthCount, 3)
        let restored = f.store()
        XCTAssertEqual(restored.current, store.current)
        XCTAssertEqual(restored.events, store.events)
        XCTAssertNil(restored.latestRestReward)
        let rolls = restored.current.weeklyJourney?.weeks.first?.encounterRolls
        XCTAssertTrue(restored.completeRest(profileID: restored.current.id, id: UUID(), seconds: 20,
            date: f.monday.addingTimeInterval(2 * 86_400 + 21_600)))
        XCTAssertEqual(restored.current.weeklyJourney?.weeks.first?.encounterRolls, rolls)
    }

    @MainActor
    func testSkippedRestDoesNotRollAndBackupRestoreDoesNotReplayEncounters() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        XCTAssertTrue(store.skipRest(profileID: store.current.id, id: UUID(), seconds: 20, date: f.monday))
        XCTAssertTrue(store.current.weeklyJourney!.weeks.isEmpty)
        for day in 0..<3 {
            XCTAssertTrue(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20,
                date: f.monday.addingTimeInterval(Double(day * 86_400))))
        }
        let snapshot = try store.snapshot()
        let backup = try RestlingBackup.decode(RestlingBackup(forest: snapshot,
            settings: BackupSettings(), createdAt: f.monday).encoded())
        XCTAssertEqual(backup.forest.version, 4)
        XCTAssertEqual(backup.forest, snapshot)
        XCTAssertFalse(store.current.weeklyJourney!.weeks[0].encounters.isEmpty)
        try store.replace(with: backup.forest)
        XCTAssertEqual(try store.snapshot(), snapshot)
        XCTAssertNil(store.latestRestReward)
        XCTAssertEqual(f.store().current.weeklyJourney?.weeks[0].encounterRolls,
                       store.current.weeklyJourney?.weeks[0].encounterRolls)
    }

    @MainActor
    func testV3UpgradePreservesOriginalBytesAndDoesNotInventOldEncounters() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let originalStore = f.store()
        for day in 0..<3 {
            XCTAssertTrue(originalStore.completeRest(profileID: originalStore.current.id, id: UUID(), seconds: 20,
                date: f.monday.addingTimeInterval(Double(day * 86_400))))
        }
        let encoded = try JSONEncoder().encode(originalStore.snapshot())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 3
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        var journey = try XCTUnwrap(profiles[0]["weeklyJourney"] as? [String: Any])
        var starting = try XCTUnwrap(journey["startingWeek"] as? [String: Any])
        starting.removeValue(forKey: "encounterRolls")
        journey["startingWeek"] = starting
        var weeks = try XCTUnwrap(journey["weeks"] as? [[String: Any]])
        for index in weeks.indices { weeks[index].removeValue(forKey: "encounterRolls") }
        journey["weeks"] = weeks
        profiles[0]["weeklyJourney"] = journey
        object["profiles"] = profiles
        let originalBytes = try JSONSerialization.data(withJSONObject: object)
        f.defaults.set(originalBytes, forKey: "forestProfiles.v1")
        let old = try JSONDecoder().decode(ForestArchive.self, from: originalBytes)
        let upgraded = f.store(at: f.monday.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(upgraded.current, old.profiles[0])
        XCTAssertEqual(upgraded.events, old.events)
        XCTAssertEqual(try upgraded.snapshot().version, 4)
        XCTAssertNil(upgraded.current.weeklyJourney?.weeks[0].encounterRolls)
        XCTAssertTrue(upgraded.current.weeklyJourney!.weeks[0].encounters.isEmpty)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.legacyV3Backup"), originalBytes)
        XCTAssertTrue(upgraded.completeRest(profileID: upgraded.current.id, id: UUID(), seconds: 20,
            date: f.monday.addingTimeInterval(3 * 86_400)))
        XCTAssertEqual(upgraded.current.weeklyJourney?.weeks[0].encounterRolls?.count, 1)
        XCTAssertEqual(f.store().current, upgraded.current)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.legacyV3Backup"), originalBytes)
    }
}
