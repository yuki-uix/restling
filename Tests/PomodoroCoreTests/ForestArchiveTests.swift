import Foundation
import XCTest
@testable import PomodoroCore

final class ForestArchiveTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000.123_456)

    func testArchiveKeepsHistoricalGrowthWithoutInventingEvents() throws {
        var profile = ForestProfile(name: "原来的森林")
        for _ in 0..<6 { XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20, date: date)) }
        profile.selectedSpecies = .blossom
        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                        recordingStartedAt: date)
        let restored = try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored, archive)
        XCTAssertEqual(restored.profiles.first?.completedRests, 6)
        XCTAssertEqual(restored.profiles.first?.totalRestSeconds, 120)
        XCTAssertEqual(restored.profiles.first?.trees, profile.trees)
        XCTAssertTrue(restored.events.isEmpty)
    }

    func testCompletedAndSkippedRecordsRoundTripWithOriginalOwnersAndPreciseTimes() throws {
        var first = ForestProfile(name: "第一片")
        let second = ForestProfile(name: "第二片")
        let creditedID = UUID()
        first.recordRest(id: creditedID, seconds: 20, date: date)
        let events = [
            ForestRestEvent(id: creditedID, profileID: first.id, occurredAt: date,
                            configuredSeconds: 20, outcome: .completed),
            ForestRestEvent(profileID: second.id, occurredAt: date.addingTimeInterval(1.125),
                            configuredSeconds: 60, outcome: .skipped)
        ]
        let archive = try ForestArchive(profiles: [first, second], activeProfileID: second.id,
                                        events: events, recordingStartedAt: date.addingTimeInterval(100))
        let restored = try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored, archive)
        XCTAssertEqual(restored.events, events)
        XCTAssertEqual(restored.profiles[0].seed, first.seed)
        XCTAssertTrue(restored.profiles[0].containsCreditedRestID(creditedID))
        XCTAssertFalse(restored.profiles[1].containsCreditedRestID(events[1].id))
        // A clock change or migration baseline is not evidence an event is bad.
        XCTAssertLessThan(restored.events[0].occurredAt, restored.recordingStartedAt)
    }

    func testInvalidProfileCollectionsAndProgrammaticSelectionsAreRejected() throws {
        let profile = ForestProfile(name: "森林")
        XCTAssertThrowsError(try ForestArchive(profiles: [], activeProfileID: profile.id))
        XCTAssertThrowsError(try ForestArchive(profiles: [profile, profile], activeProfileID: profile.id))
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: UUID()))
        var invalidName = profile
        invalidName.name = " "
        XCTAssertThrowsError(try ForestArchive(profiles: [invalidName], activeProfileID: invalidName.id))
        var lockedSelection = profile
        lockedSelection.selectedSpecies = .blossom
        XCTAssertThrowsError(try ForestArchive(profiles: [lockedSelection], activeProfileID: lockedSelection.id))
    }

    func testDuplicateRecordsAndUnknownOwnersAreRejected() throws {
        let profile = ForestProfile(name: "森林")
        let skipped = ForestRestEvent(profileID: profile.id, occurredAt: date,
                                      configuredSeconds: 20, outcome: .skipped)
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               events: [skipped, skipped]))
        let unknown = ForestRestEvent(profileID: UUID(), occurredAt: date,
                                      configuredSeconds: 20, outcome: .skipped)
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               events: [unknown]))
    }

    func testCompletedEventsMustMatchCreditedIDsAndCannotExceedTheirCumulativeTime() throws {
        var profile = ForestProfile(name: "森林")
        let restID = UUID()
        profile.recordRest(id: restID, seconds: 20, date: date)
        let uncredited = ForestRestEvent(profileID: profile.id, occurredAt: date,
                                         configuredSeconds: 20, outcome: .completed)
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               events: [uncredited]))
        let inflated = ForestRestEvent(id: restID, profileID: profile.id, occurredAt: date,
                                       configuredSeconds: 21, outcome: .completed)
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               events: [inflated]))
        let valid = ForestRestEvent(id: restID, profileID: profile.id, occurredAt: date,
                                    configuredSeconds: 20, outcome: .completed)
        XCTAssertNoThrow(try ForestArchive(profiles: [profile], activeProfileID: profile.id, events: [valid]))
    }

    func testSkippedIDCannotBeCreditedInEitherItsOwnerOrAnotherForest() throws {
        var first = ForestProfile(name: "第一片")
        let second = ForestProfile(name: "第二片")
        let restID = UUID()
        first.recordRest(id: restID, seconds: 20, date: date)
        for owner in [first.id, second.id] {
            let skipped = ForestRestEvent(id: restID, profileID: owner, occurredAt: date,
                                          configuredSeconds: 20, outcome: .skipped)
            XCTAssertThrowsError(try ForestArchive(profiles: [first, second], activeProfileID: first.id,
                                                   events: [skipped]))
        }
    }

    func testInvalidEventDatesAndDurationsCannotBeValidatedOrEncoded() throws {
        let profile = ForestProfile(name: "森林")
        for seconds in [0.0, -1, .nan, .infinity, 86_401] {
            let event = ForestRestEvent(profileID: profile.id, configuredSeconds: seconds, outcome: .skipped)
            XCTAssertThrowsError(try event.validate())
            XCTAssertThrowsError(try JSONEncoder().encode(event))
            XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id, events: [event]))
        }
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let event = ForestRestEvent(profileID: profile.id, occurredAt: invalidDate,
                                    configuredSeconds: 20, outcome: .skipped)
        XCTAssertThrowsError(try event.validate())
        XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                               recordingStartedAt: invalidDate))
    }

    func testArchiveDecoderRejectsUnknownOrMissingVersions() throws {
        let profile = ForestProfile(name: "森林")
        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id)
        let data = try JSONEncoder().encode(archive)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for version in [1, 3] {
            var malformed = original
            malformed["version"] = version
            XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
                from: JSONSerialization.data(withJSONObject: malformed)))
        }
        var missing = original
        missing.removeValue(forKey: "recordingStartedAt")
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
            from: JSONSerialization.data(withJSONObject: missing)))
    }

    func testArchiveDecoderDoesNotSilentlyNormalizeInvalidImportedProfileChoices() throws {
        let profile = ForestProfile(name: "森林")
        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        for (key, value) in [("name", "  "), ("selectedSpecies", "blossom")] {
            var altered = original
            var profiles = try XCTUnwrap(altered["profiles"] as? [[String: Any]])
            profiles[0][key] = value
            altered["profiles"] = profiles
            XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
                from: JSONSerialization.data(withJSONObject: altered)))
        }
    }

    func testAllForestDatesRejectExtremeFiniteValuesAndAcceptGregorianEndpoints() throws {
        for seconds in [-62_135_596_801.0, 253_402_300_800, 1e300, -1e300] {
            let outside = Date(timeIntervalSince1970: seconds)
            var profile = ForestProfile(name: "森林")
            let event = ForestRestEvent(profileID: profile.id, occurredAt: outside,
                                        configuredSeconds: 20, outcome: .skipped)
            XCTAssertThrowsError(try event.validate())
            XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                                   recordingStartedAt: outside))
            for _ in 0..<3 { XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20, date: outside)) }
            XCTAssertThrowsError(try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                                   recordingStartedAt: date))
        }
        for seconds in [-62_135_596_800.0, 253_402_300_799.5] {
            let endpoint = Date(timeIntervalSince1970: seconds)
            var profile = ForestProfile(name: "森林")
            for _ in 0..<3 { XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20, date: endpoint)) }
            let event = ForestRestEvent(profileID: profile.id, occurredAt: endpoint,
                                        configuredSeconds: 20, outcome: .skipped)
            let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                            events: [event], recordingStartedAt: endpoint)
            XCTAssertEqual(try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(archive)), archive)
        }
    }

    func testRawImportedTreeDateCannotBypassArchiveValidation() throws {
        var profile = ForestProfile(name: "森林")
        for _ in 0..<3 { profile.recordRest(id: UUID(), seconds: 20, date: date) }
        let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var profiles = try XCTUnwrap(raw["profiles"] as? [[String: Any]])
        var trees = try XCTUnwrap(profiles[0]["trees"] as? [[String: Any]])
        trees[0]["plantedAt"] = 1e300
        profiles[0]["trees"] = trees
        raw["profiles"] = profiles
        XCTAssertThrowsError(try JSONDecoder().decode(ForestArchive.self,
            from: JSONSerialization.data(withJSONObject: raw)))
    }
}
