import Foundation
import XCTest
@testable import PomodoroCore

final class ForestWeeklyJourneyTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private var monday: Date { date("2026-11-16T10:00:00Z") }

    private func weekly(name: String = "本周森林") -> ForestProfile {
        var profile = ForestProfile(name: name)
        XCTAssertTrue(profile.enableWeeklyGrowth(at: monday, calendar: calendar()))
        return profile
    }

    @discardableResult
    private func complete(_ profile: inout ForestProfile, count: Int, at date: Date,
                          seconds: TimeInterval = 20, calendar: Calendar? = nil) -> [ForestRestEvent] {
        var events: [ForestRestEvent] = []
        for offset in 0..<count {
            let id = UUID()
            let terminal = date.addingTimeInterval(Double(offset))
            XCTAssertTrue(profile.recordRest(id: id, seconds: seconds, date: terminal,
                                             calendar: calendar ?? self.calendar()))
            events.append(ForestRestEvent(id: id, profileID: profile.id, occurredAt: terminal,
                                          configuredSeconds: seconds, outcome: .completed))
        }
        return events
    }

    private func object(_ profile: ForestProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    }

    private func assertInvalid(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try JSONDecoder().decode(ForestProfile.self,
            from: JSONSerialization.data(withJSONObject: object)), file: file, line: line)
    }

    func testNewForestHasFastFirstTreeThenTwentyFourRestCycles() throws {
        var profile = weekly()
        XCTAssertEqual(profile.growthCount, 0)
        XCTAssertEqual(profile.growthTarget, 3)
        XCTAssertTrue(try XCTUnwrap(profile.weeklyJourney).weeks.isEmpty)
        complete(&profile, count: 2, at: monday)
        XCTAssertEqual(profile.growthCount, 2)
        XCTAssertEqual(profile.growthStage, 2)
        XCTAssertEqual(profile.restsUntilTree, 1)
        XCTAssertTrue(profile.trees.isEmpty)
        let first = complete(&profile, count: 1, at: monday.addingTimeInterval(2))
        XCTAssertEqual(profile.trees.map(\.id), first.map(\.id))
        XCTAssertEqual(profile.growthTarget, 24)
        XCTAssertEqual(profile.growthCount, 0)
        profile.selectedSpecies = .pine
        complete(&profile, count: 23, at: monday.addingTimeInterval(3))
        XCTAssertEqual(profile.trees.count, 1)
        XCTAssertEqual(profile.growthCount, 23)
        XCTAssertEqual(profile.growthProgress, 23.0 / 24)
        XCTAssertEqual(profile.restsUntilTree, 1)
        let second = complete(&profile, count: 1, at: monday.addingTimeInterval(26))
        XCTAssertEqual(profile.completedRests, 27)
        XCTAssertEqual(profile.trees.map(\.species), [.oak, .pine])
        XCTAssertEqual(profile.trees.last?.id, second.first?.id)
        XCTAssertEqual(profile.growthCount, 0)
        XCTAssertEqual(profile.restsUntilTree, 24)
    }

    func testMigrationRetainsEveryOldAssetAndFinishesTheExistingSeedBeforeSlowing() throws {
        var profile = ForestProfile(name: "最初的森林")
        complete(&profile, count: 35, at: date("2020-01-01T10:00:00Z"))
        profile.selectedSpecies = .pine
        let old = profile
        XCTAssertTrue(profile.enableWeeklyGrowth(at: monday, calendar: calendar()))
        let journey = try XCTUnwrap(profile.weeklyJourney)
        XCTAssertEqual(profile.id, old.id)
        XCTAssertEqual(profile.name, old.name)
        XCTAssertEqual(profile.seed, old.seed)
        XCTAssertEqual(profile.trees, old.trees)
        XCTAssertEqual(profile.legacyTrees, old.trees)
        XCTAssertEqual(profile.completedRests, old.completedRests)
        XCTAssertEqual(profile.totalRestSeconds, old.totalRestSeconds)
        XCTAssertEqual(journey.legacyCompletedRests, 35)
        XCTAssertEqual(journey.legacyTreeCount, 11)
        XCTAssertEqual(journey.legacyRestSeconds, 700)
        XCTAssertEqual(journey.legacySelectedSpecies, .pine)
        XCTAssertTrue(journey.weeks.isEmpty)
        XCTAssertEqual(profile.growthCount, 2)
        XCTAssertEqual(profile.growthTarget, 3)
        complete(&profile, count: 1, at: monday)
        XCTAssertEqual(Array(profile.trees.dropLast()), old.trees)
        XCTAssertEqual(profile.trees.last?.species, .pine)
        XCTAssertEqual(profile.growthTarget, 24)
        XCTAssertEqual(profile.growthCount, 0)
        let after = profile
        XCTAssertFalse(profile.enableWeeklyGrowth(at: monday.addingTimeInterval(86_400), calendar: calendar()))
        XCTAssertEqual(profile, after)
    }

    func testMigrationAtATreeBoundaryStartsANewSlowCycleWithoutGrantingATree() {
        var profile = ForestProfile(name: "旧林地")
        complete(&profile, count: 48, at: monday)
        XCTAssertTrue(profile.enableWeeklyGrowth(at: monday, calendar: calendar()))
        XCTAssertEqual(profile.trees.count, 16)
        XCTAssertEqual(profile.growthTarget, 24)
        XCTAssertEqual(profile.restsUntilTree, 24)
        complete(&profile, count: 23, at: monday)
        XCTAssertEqual(profile.trees.count, 16)
        complete(&profile, count: 1, at: monday)
        XCTAssertEqual(profile.trees.count, 17)
    }

    func testMondayBoundaryCarriesSeedAndMaturityBelongsToCompletionWeek() throws {
        var profile = weekly()
        complete(&profile, count: 2, at: date("2026-11-22T23:59:57Z"))
        let previous = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        XCTAssertEqual(previous.id, "2026-11-16")
        XCTAssertEqual(previous.completedRests, 2)
        XCTAssertEqual(previous.lastGrowthCount, 2)
        XCTAssertEqual(previous.lastGrowthTarget, 3)
        XCTAssertTrue(previous.treeIDs.isEmpty)
        let completion = complete(&profile, count: 1, at: date("2026-11-23T00:00:00Z"))
        let weeks = try XCTUnwrap(profile.weeklyJourney).weeks
        XCTAssertEqual(weeks.map(\.id), ["2026-11-16", "2026-11-23"])
        XCTAssertEqual(weeks.first, previous)
        XCTAssertEqual(weeks.last?.treeIDs, completion.map(\.id))
        XCTAssertEqual(weeks.last?.lastGrowthCount, 0)
        XCTAssertEqual(weeks.last?.lastGrowthTarget, 24)
        XCTAssertEqual(profile.restsUntilTree, 24)
    }

    func testUnusedWeeksRemainAbsentAndViewingAnEmptyWeekIsReadOnly() throws {
        var profile = weekly()
        let original = profile
        let empty = try XCTUnwrap(profile.weeklyJourney).displayWeek(at: date("2026-11-30T10:00:00Z"), calendar: calendar())
        XCTAssertEqual(empty.id, "2026-11-30")
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(profile, original)
        complete(&profile, count: 1, at: monday)
        let recorded = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        let emptyNext = try XCTUnwrap(profile.weeklyJourney).displayWeek(at: date("2026-12-07T10:00:00Z"), calendar: calendar())
        XCTAssertTrue(emptyNext.isEmpty)
        XCTAssertEqual(profile.weeklyJourney?.weeks, [recorded])
        complete(&profile, count: 1, at: date("2026-12-07T10:00:00Z"))
        XCTAssertEqual(profile.weeklyJourney?.weeks.map(\.id), ["2026-11-16", "2026-12-07"])
    }

    func testClockRollbackCannotReopenOrMutateAnArchivedWeek() throws {
        var profile = weekly()
        complete(&profile, count: 1, at: monday)
        let first = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        complete(&profile, count: 1, at: date("2026-12-07T10:00:00Z"))
        let active = try XCTUnwrap(profile.weeklyJourney).displayWeek(at: monday, calendar: calendar())
        XCTAssertEqual(active.id, "2026-12-07")
        complete(&profile, count: 1, at: monday)
        XCTAssertEqual(profile.weeklyJourney?.weeks.first, first)
        XCTAssertEqual(profile.weeklyJourney?.weeks.last?.completedRests, 2)
        XCTAssertEqual(profile.weeklyJourney?.weeks.last?.treeIDs, [profile.trees[0].id])
    }

    func testTimezoneChangesRetainRecordedHeadersAndDoNotDuplicateCivilWeeks() throws {
        var profile = weekly()
        complete(&profile, count: 1, at: date("2026-11-23T01:00:00Z"))
        let utc = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        XCTAssertEqual(utc.id, "2026-11-23")
        complete(&profile, count: 1, at: date("2026-11-23T01:00:01Z"), calendar: calendar("America/Los_Angeles"))
        XCTAssertEqual(profile.weeklyJourney?.weeks.count, 1)
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.timeZoneIdentifier, utc.timeZoneIdentifier)
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.startDate, utc.startDate)
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.completedRests, 2)
    }

    func testGregorianWeeksHonorDSTAndCalendarYearBoundaries() throws {
        let spring = try XCTUnwrap(ForestWeek.containing(date("2026-03-08T12:00:00-07:00"), calendar: calendar("America/Los_Angeles")))
        XCTAssertEqual(spring.id, "2026-03-02")
        XCTAssertEqual(spring.endDate.timeIntervalSince(spring.startDate), 601_200)
        let fall = try XCTUnwrap(ForestWeek.containing(date("2026-11-01T12:00:00-08:00"), calendar: calendar("America/Los_Angeles")))
        XCTAssertEqual(fall.id, "2026-10-26")
        XCTAssertEqual(fall.endDate.timeIntervalSince(fall.startDate), 608_400)
        let newYear = try XCTUnwrap(ForestWeek.containing(date("2027-01-01T12:00:00Z"), calendar: calendar()))
        XCTAssertEqual(newYear.id, "2026-12-28")
        XCTAssertEqual(newYear.year, 2026)
        XCTAssertEqual(newYear.monthID, "2026-12")
        XCTAssertEqual(ForestWeek.containing(date("2027-01-04T00:00:00Z"), calendar: calendar())?.id, "2027-01-04")
        var nonGregorian = Calendar(identifier: .buddhist)
        nonGregorian.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ForestWeek.containing(monday, calendar: nonGregorian)?.id, "2026-11-16")
    }

    func testDuplicateRewardsAndInvalidDatesNeverChangeAWeeklyJourney() {
        var profile = weekly()
        let events = complete(&profile, count: 3, at: monday)
        let saved = profile
        XCTAssertFalse(profile.recordRest(id: events[0].id, seconds: 20, date: monday, calendar: calendar()))
        for value in [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: 1e18)] {
            XCTAssertFalse(profile.recordRest(id: UUID(), seconds: 20, date: value, calendar: calendar()))
            XCTAssertEqual(profile, saved)
        }
    }

    func testHistoryKeepsItsSpeciesAndGrowthSnapshotAfterCurrentSelectionChanges() throws {
        var profile = weekly()
        complete(&profile, count: 4, at: monday)
        let first = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        XCTAssertEqual(first.lastSpecies, .oak)
        XCTAssertEqual(first.lastGrowthCount, 1)
        XCTAssertEqual(first.lastGrowthTarget, 24)
        profile.selectedSpecies = .pine
        complete(&profile, count: 2, at: date("2026-11-23T10:00:00Z"))
        XCTAssertEqual(profile.weeklyJourney?.weeks.first, first)
        XCTAssertEqual(profile.weeklyJourney?.weeks.last?.lastSpecies, .pine)
        XCTAssertEqual(profile.weeklyJourney?.weeks.last?.lastGrowthCount, 3)
    }

    func testLayoutMovesAndSwapsOnlyCurrentWeekWithoutChangingEarnedTrees() throws {
        var profile = weekly()
        complete(&profile, count: 51, at: monday)
        let oldTrees = profile.trees
        let oldCount = profile.completedRests
        let weekID = try XCTUnwrap(profile.weeklyJourney?.weeks.first?.id)
        XCTAssertTrue(profile.moveTree(id: oldTrees[0].id, to: 15, inWeekID: weekID, at: monday, calendar: calendar()))
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.slot(for: oldTrees[0].id), 15)
        XCTAssertTrue(profile.moveTree(id: oldTrees[1].id, to: 15, inWeekID: weekID, at: monday, calendar: calendar()))
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.slot(for: oldTrees[0].id), 1)
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.slot(for: oldTrees[1].id), 15)
        XCTAssertFalse(profile.moveTree(id: oldTrees[0].id, to: -1, inWeekID: weekID, at: monday, calendar: calendar()))
        XCTAssertFalse(profile.moveTree(id: oldTrees[0].id, to: 16, inWeekID: weekID, at: monday, calendar: calendar()))
        XCTAssertFalse(profile.moveTree(id: oldTrees[0].id, to: 4, inWeekID: weekID,
                                        at: date("2026-11-23T10:00:00Z"), calendar: calendar()))
        XCTAssertEqual(profile.trees, oldTrees)
        XCTAssertEqual(profile.completedRests, oldCount)
        XCTAssertEqual(profile.weeklyJourney?.weeks.first?.treeIDs, oldTrees.map(\.id))
        XCTAssertNoThrow(try JSONDecoder().decode(ForestProfile.self, from: JSONEncoder().encode(profile)))
    }

    func testUnusuallyBusyWeeksKeepOverflowTreesOnAdditionalPages() throws {
        var profile = weekly()
        complete(&profile, count: 387, at: monday)
        let week = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        XCTAssertEqual(profile.trees.count, 17)
        XCTAssertEqual(week.pageCount, 2)
        XCTAssertEqual(week.slot(for: profile.trees[16].id), 16)
        XCTAssertEqual(Set(week.placements.map(\.treeID)), Set(profile.trees.map(\.id)))
        XCTAssertNoThrow(try JSONDecoder().decode(ForestProfile.self, from: JSONEncoder().encode(profile)))
    }

    func testTamperedBaselineWeekGrowthAndLayoutAreRejected() throws {
        var profile = weekly()
        complete(&profile, count: 3, at: monday)
        let valid = try object(profile)
        for key in ["legacyCompletedRests", "legacyTreeCount", "legacyRestSeconds"] {
            var changed = valid
            var journey = try XCTUnwrap(changed["weeklyJourney"] as? [String: Any])
            journey[key] = 1
            changed["weeklyJourney"] = journey
            try assertInvalid(changed)
        }
        for (key, value) in [("id", "2026-11-17" as Any), ("timeZoneIdentifier", "Invalid/Zone" as Any),
                             ("lastGrowthCount", 7 as Any), ("lastGrowthTarget", 3 as Any),
                             ("totalRestSeconds", 61 as Any), ("restIDs", [] as Any),
                             ("treeIDs", [] as Any), ("placements", [] as Any)] {
            var changed = valid
            var journey = try XCTUnwrap(changed["weeklyJourney"] as? [String: Any])
            var weeks = try XCTUnwrap(journey["weeks"] as? [[String: Any]])
            weeks[0][key] = value
            journey["weeks"] = weeks
            changed["weeklyJourney"] = journey
            try assertInvalid(changed)
        }
    }

    func testWeeklyArchiveUsesVersionThreeAndRequiresMatchingAtomicEvents() throws {
        var profile = weekly()
        let events = complete(&profile, count: 3, at: monday)
        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                        events: events, recordingStartedAt: monday)
        XCTAssertEqual(archive.version, 3)
        XCTAssertEqual(try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(archive)), archive)
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               recordingStartedAt: monday))
        var wrongSeconds = events
        wrongSeconds[0] = ForestRestEvent(id: events[0].id, profileID: profile.id, occurredAt: monday,
                                         configuredSeconds: 21, outcome: .completed)
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               events: wrongSeconds, recordingStartedAt: monday))
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        encoded["version"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
            from: JSONSerialization.data(withJSONObject: encoded)))
    }

    func testForgedNewTreeSpeciesOrDateCannotBeImportedAsWeeklyGrowth() throws {
        var profile = weekly()
        let events = complete(&profile, count: 3, at: monday)
        var forged = try object(profile)
        var trees = try XCTUnwrap(forged["trees"] as? [[String: Any]])
        trees[0]["species"] = "ginkgo"
        forged["trees"] = trees
        try assertInvalid(forged)

        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                        events: events, recordingStartedAt: monday)
        var archiveObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var profiles = try XCTUnwrap(archiveObject["profiles"] as? [[String: Any]])
        trees = try XCTUnwrap(profiles[0]["trees"] as? [[String: Any]])
        trees[0]["plantedAt"] = monday.addingTimeInterval(1_000).timeIntervalSinceReferenceDate
        profiles[0]["trees"] = trees
        archiveObject["profiles"] = profiles
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
            from: JSONSerialization.data(withJSONObject: archiveObject)))
    }

    func testWeeklyBackupRoundTripRetainsSnapshotsPlacementsAndLegacyBaseline() throws {
        var profile = ForestProfile(name: "旧森林")
        complete(&profile, count: 5, at: monday.addingTimeInterval(-86_400))
        let oldTrees = profile.trees
        XCTAssertTrue(profile.enableWeeklyGrowth(at: monday, calendar: calendar()))
        let events = complete(&profile, count: 26, at: monday)
        XCTAssertTrue(profile.moveTree(id: profile.trees.last!.id, to: 14, inWeekID: "2026-11-16",
                                       at: monday, calendar: calendar()))
        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                        events: events, recordingStartedAt: monday)
        let backup = try RestlingBackup(forest: archive, settings: BackupSettings(), createdAt: monday)
        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.forest.version, 3)
        let decoded = try RestlingBackup.decode(backup.encoded())
        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(decoded.forest.profiles[0].legacyTrees, oldTrees)
        XCTAssertEqual(decoded.forest.profiles[0].weeklyJourney?.weeks.first?.slot(for: profile.trees.last!.id), 14)
    }
}
