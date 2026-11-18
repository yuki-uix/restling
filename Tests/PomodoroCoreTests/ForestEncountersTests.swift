import Foundation
import XCTest
@testable import PomodoroCore

final class ForestEncountersTests: XCTestCase {
    private let monday = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00Z")!

    private func calendar(_ zone: String = "UTC") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(number)))!
    }

    private func profile(seed: UInt64 = 108, zone: String = "UTC") throws -> ForestProfile {
        let original = ForestProfile(name: "林间偶遇")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["seed"] = seed
        var value = try JSONDecoder().decode(ForestProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(value.enableWeeklyGrowth(at: monday, calendar: calendar(zone)))
        return value
    }

    private func complete(_ profile: inout ForestProfile, _ number: Int, day: Int = 0,
                          secondsOffset: TimeInterval = 0, zone: String = "UTC") -> ForestRestEvent {
        let date = monday.addingTimeInterval(Double(day) * 86_400 + secondsOffset)
        let id = uuid(number)
        XCTAssertTrue(profile.recordRest(id: id, seconds: 20, date: date, calendar: calendar(zone)))
        return ForestRestEvent(id: id, profileID: profile.id, occurredAt: date,
                               configuredSeconds: 20, outcome: .completed)
    }

    private func archive(_ profile: ForestProfile, events: [ForestRestEvent]) throws -> ForestArchive {
        try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                          events: events, recordingStartedAt: monday)
    }

    private func json(_ archive: ForestArchive) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
    }

    private func mutateFirstWeek(_ archive: ForestArchive,
                                 _ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var object = try json(archive)
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        var journey = try XCTUnwrap(profiles[0]["weeklyJourney"] as? [String: Any])
        var weeks = try XCTUnwrap(journey["weeks"] as? [[String: Any]])
        mutate(&weeks[0])
        journey["weeks"] = weeks
        profiles[0]["weeklyJourney"] = journey
        object["profiles"] = profiles
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testDailyMissIsSavedAndMoreRestsOrRelaunchDoNotReroll() throws {
        var forest = try profile()
        var events = [complete(&forest, 1)]
        XCTAssertNil(forest.weeklyJourney?.weeks[0].encounterRolls?.first?.kind)
        events.append(complete(&forest, 2, secondsOffset: 1_200))
        let saved = try archive(forest, events: events)
        let restored = try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(saved))
        forest = restored.profiles[0]
        XCTAssertEqual(forest.weeklyJourney?.weeks[0].encounterRolls?.count, 1)
        XCTAssertEqual(forest.weeklyJourney?.weeks[0].encounters.count, 0)
        events.append(complete(&forest, 7, secondsOffset: 2_400))
        XCTAssertEqual(forest.weeklyJourney?.weeks[0].encounterRolls?.count, 1)
        XCTAssertEqual(forest.completedRests, 3)
        XCTAssertEqual(forest.trees.count, 1)
        XCTAssertEqual(forest.totalRestSeconds, 60)
        XCTAssertNoThrow(try archive(forest, events: events))
    }

    func testThirdUsedDayGuaranteesAnEncounterWithoutConsecutiveAttendance() throws {
        var forest = try profile()
        let events = [complete(&forest, 1), complete(&forest, 3, day: 2), complete(&forest, 4, day: 5)]
        let week = try XCTUnwrap(forest.weeklyJourney?.weeks.first)
        XCTAssertEqual(week.encounterRolls?.map(\.kind), [nil, nil, .bluebird])
        XCTAssertEqual(week.encounters.map(\.id), [uuid(4)])
        XCTAssertEqual(forest.trees.count, 1)
        XCTAssertEqual(forest.growthCount, 0)
        XCTAssertNoThrow(try archive(forest, events: events))
    }

    func testFixedSeedAndRestIDsKeepTheSameOutcomesAndWeeklyCap() throws {
        var forest = try profile()
        var same = try profile()
        var events: [ForestRestEvent] = []
        for day in 0..<7 {
            events.append(complete(&forest, day + 1, day: day))
            _ = complete(&same, day + 1, day: day)
        }
        let week = try XCTUnwrap(forest.weeklyJourney?.weeks.first)
        XCTAssertEqual(week.encounterRolls, same.weeklyJourney?.weeks.first?.encounterRolls)
        XCTAssertEqual(week.encounterRolls?.count, 7)
        XCTAssertEqual(week.encounters.map(\.kind), [.goldenMushrooms, .bluebird])
        XCTAssertEqual(Set(week.encounters.compactMap(\.kind)).count, 2)
        let saved = try archive(forest, events: events)
        XCTAssertEqual(saved.version, 4)
        XCTAssertEqual(try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(saved)), saved)
        XCTAssertEqual(forest.completedRests, 7)
        XCTAssertEqual(forest.trees.count, 1)
        XCTAssertEqual(forest.growthCount, 4)
    }

    func testChangingTheDeviceTimezoneDoesNotChangeTheRecordedWeekDay() throws {
        var forest = try profile(zone: "Asia/Shanghai")
        let first = complete(&forest, 1, secondsOffset: 5 * 3_600 + 59 * 60, zone: "Asia/Shanghai")
        // UTC date stays Nov 23, but the retained forest's local date is now Nov 24.
        let second = complete(&forest, 2, secondsOffset: 6 * 3_600 + 60, zone: "UTC")
        let third = complete(&forest, 7, secondsOffset: 8 * 3_600, zone: "UTC")
        let week = try XCTUnwrap(forest.weeklyJourney?.weeks.first)
        XCTAssertEqual(week.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(week.encounterRolls?.map(\.id), [uuid(1), uuid(2)])
        XCTAssertNoThrow(try archive(forest, events: [first, second, third]))
    }

    func testClockRollbackCreditsTheRestWithoutInventingAnOldDatedEncounter() throws {
        var forest = try profile()
        let first = complete(&forest, 1)
        let later = complete(&forest, 2, day: 14)
        let current = try XCTUnwrap(forest.weeklyJourney?.weeks.last)
        let rollback = complete(&forest, 3, day: 1)
        XCTAssertEqual(forest.completedRests, 3)
        XCTAssertEqual(forest.weeklyJourney?.weeks.last?.id, current.id)
        XCTAssertEqual(forest.weeklyJourney?.weeks.last?.encounterRolls, current.encounterRolls)
        XCTAssertNoThrow(try archive(forest, events: [first, later, rollback]))
    }

    func testSkippedEventsAndReadingTheForestDoNotCreateAnyChance() throws {
        let forest = try profile()
        let skipped = ForestRestEvent(id: uuid(1), profileID: forest.id, occurredAt: monday,
                                      configuredSeconds: 20, outcome: .skipped)
        let original = forest
        for _ in 0..<3 {
            _ = forest.weeklyJourney?.displayWeek(at: monday.addingTimeInterval(86_400), calendar: calendar())
        }
        let restored = try JSONDecoder().decode(ForestArchive.self,
            from: JSONEncoder().encode(archive(forest, events: [skipped])))
        XCTAssertEqual(forest, original)
        XCTAssertEqual(restored.profiles[0].completedRests, 0)
        XCTAssertTrue(restored.profiles[0].weeklyJourney?.weeks.isEmpty == true)
    }

    func testOldV3ArchiveIsReadWithoutBackfillingAndOnlyNewRestsDraw() throws {
        var forest = try profile()
        var events = [complete(&forest, 1), complete(&forest, 2, day: 1), complete(&forest, 3, day: 2)]
        let beforeTrees = forest.trees
        var object = try json(archive(forest, events: events))
        object["version"] = 3
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        var journey = try XCTUnwrap(profiles[0]["weeklyJourney"] as? [String: Any])
        var start = try XCTUnwrap(journey["startingWeek"] as? [String: Any])
        start.removeValue(forKey: "encounterRolls")
        journey["startingWeek"] = start
        var weeks = try XCTUnwrap(journey["weeks"] as? [[String: Any]])
        for index in weeks.indices { weeks[index].removeValue(forKey: "encounterRolls") }
        journey["weeks"] = weeks
        profiles[0]["weeklyJourney"] = journey
        object["profiles"] = profiles
        let old = try JSONDecoder().decode(ForestArchive.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.version, 3)
        forest = old.profiles[0]
        XCTAssertNil(forest.weeklyJourney?.weeks.first?.encounterRolls)
        XCTAssertTrue(forest.weeklyJourney?.weeks.first?.encounters.isEmpty == true)
        XCTAssertEqual(forest.trees, beforeTrees)
        XCTAssertEqual(try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(old)), old)
        events.append(complete(&forest, 7, day: 3))
        XCTAssertEqual(forest.weeklyJourney?.weeks.first?.encounterRolls?.map(\.id), [uuid(7)])
        XCTAssertEqual(forest.trees, beforeTrees)
        XCTAssertEqual(try archive(forest, events: events).version, 4)
    }

    func testEncountersStayInTheirOwnWeekAndBackupRoundTrip() throws {
        var forest = try profile()
        let first = complete(&forest, 2)
        let firstWeek = try XCTUnwrap(forest.weeklyJourney?.weeks.first)
        let second = complete(&forest, 7, day: 7)
        XCTAssertEqual(forest.weeklyJourney?.weeks.first, firstWeek)
        XCTAssertEqual(firstWeek.encounters.map(\.kind), [.goldenMushrooms])
        let saved = try archive(forest, events: [first, second])
        let backup = try RestlingBackup(forest: saved, settings: BackupSettings(), createdAt: monday)
        let restored = try RestlingBackup.decode(JSONEncoder().encode(backup))
        XCTAssertEqual(restored.forest, saved)
    }

    func testArchiveRejectsDuplicateDaysOrOrphanedEncounterIDs() throws {
        var forest = try profile()
        let events = [complete(&forest, 1), complete(&forest, 2, secondsOffset: 1_200)]
        let saved = try archive(forest, events: events)
        let duplicate = try mutateFirstWeek(saved) { week in
            let roll = (week["encounterRolls"] as! [[String: Any]])[0]
            week["encounterRolls"] = [roll, roll]
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self, from: duplicate))
        let orphan = try mutateFirstWeek(saved) { week in
            var rolls = week["encounterRolls"] as! [[String: Any]]
            rolls[0]["id"] = self.uuid(99).uuidString
            week["encounterRolls"] = rolls
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self, from: orphan))
    }

    func testArchiveRejectsDateMismatchOutsideWeekOrFabricatedOutcome() throws {
        var forest = try profile()
        let event = complete(&forest, 1)
        let saved = try archive(forest, events: [event])
        for date in [monday.addingTimeInterval(1), monday.addingTimeInterval(8 * 86_400)] {
            let invalid = try mutateFirstWeek(saved) { week in
                var rolls = week["encounterRolls"] as! [[String: Any]]
                rolls[0]["occurredAt"] = date.timeIntervalSinceReferenceDate
                week["encounterRolls"] = rolls
            }
            XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self, from: invalid))
        }
        let fabricated = try mutateFirstWeek(saved) { week in
            var rolls = week["encounterRolls"] as! [[String: Any]]
            rolls[0]["kind"] = "robin"
            week["encounterRolls"] = rolls
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self, from: fabricated))
    }

    func testV3EnvelopeCannotHideNewEncounterRecords() throws {
        var forest = try profile()
        let event = complete(&forest, 1)
        var object = try json(archive(forest, events: [event]))
        object["version"] = 3
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }
}
