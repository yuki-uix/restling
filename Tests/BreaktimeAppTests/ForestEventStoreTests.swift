import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ForestEventStoreTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let suite = "ForestEventStoreTests." + UUID().uuidString
        let defaults: UserDefaults
        let start = Date(timeIntervalSinceReferenceDate: 123_456)

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        }

        func store() -> ForestStore {
            ForestStore(defaults: defaults, now: { self.start })
        }

        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }

    private struct LegacyArchive: Codable {
        let version = 1
        let profiles: [ForestProfile]
        let activeProfileID: UUID
    }

    @MainActor
    func testNewStorePersistsAValidEmptyV2Archive() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        let saved = try JSONDecoder().decode(ForestArchive.self,
            from: XCTUnwrap(f.defaults.data(forKey: "forestProfiles.v1")))
        XCTAssertEqual(saved.version, 2)
        XCTAssertEqual(saved.events, [])
        XCTAssertEqual(saved.recordingStartedAt, f.start)
        XCTAssertEqual(saved.profiles, store.profiles)
        XCTAssertEqual(saved.activeProfileID, store.activeProfileID)
        XCTAssertTrue(store.canSafelyReplace)
    }

    @MainActor
    func testV1MigrationPreservesGrowthAndOriginalBytesWithoutInventingHistoricalEvents() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        var first = ForestProfile(name: "迁移前的森林")
        let oldIDs = (0..<7).map { _ in UUID() }
        for (index, id) in oldIDs.enumerated() {
            XCTAssertTrue(first.recordRest(id: id, seconds: 20,
                date: f.start.addingTimeInterval(Double(index - 100))))
        }
        first.selectedSpecies = .pine
        let second = ForestProfile(name: "另一片森林")
        let original = try JSONEncoder().encode(LegacyArchive(profiles: [first, second], activeProfileID: first.id))
        f.defaults.set(original, forKey: "forestProfiles.v1")

        let store = f.store()
        XCTAssertEqual(store.profiles, [first, second])
        XCTAssertEqual(store.current, first)
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(store.recordingStartedAt, f.start)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.legacyV1Backup"), original)
        XCTAssertEqual(try store.snapshot().version, 2)
        // A replay from an old timer remains a duplicate, not a new historical row.
        XCTAssertFalse(store.completeRest(profileID: first.id, id: oldIDs[0], seconds: 20))
        XCTAssertFalse(store.skipRest(profileID: first.id, id: oldIDs[0], seconds: 20))
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(store.current.completedRests, 7)

        let restored = ForestStore(defaults: f.defaults, now: { f.start.addingTimeInterval(1_000) })
        XCTAssertEqual(restored.profiles, [first, second])
        XCTAssertEqual(restored.recordingStartedAt, f.start)
        XCTAssertEqual(restored.events, [])
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.legacyV1Backup"), original)
    }

    @MainActor
    func testCompletionAndSkipPersistTheirExactFieldsAndOnlyCompletionAddsGrowth() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        let owner = store.current.id
        let completedID = UUID(), skippedID = UUID()
        let completedAt = f.start.addingTimeInterval(50)
        let skippedAt = f.start.addingTimeInterval(70)
        XCTAssertTrue(store.completeRest(profileID: owner, id: completedID, seconds: 20, date: completedAt))
        XCTAssertTrue(store.skipRest(profileID: owner, id: skippedID, seconds: 45, date: skippedAt))
        let expected = [
            ForestRestEvent(id: completedID, profileID: owner, occurredAt: completedAt,
                            configuredSeconds: 20, outcome: .completed),
            ForestRestEvent(id: skippedID, profileID: owner, occurredAt: skippedAt,
                            configuredSeconds: 45, outcome: .skipped)
        ]
        XCTAssertEqual(store.events, expected)
        XCTAssertEqual(store.current.completedRests, 1)
        XCTAssertEqual(store.current.totalRestSeconds, 20)
        XCTAssertTrue(store.current.trees.isEmpty)
        XCTAssertEqual(store.latestRestReward?.id, completedID)
        let restored = f.store()
        XCTAssertEqual(restored.events, expected)
        XCTAssertEqual(restored.current, store.current)
    }

    @MainActor
    func testTerminalEventIDCannotBeReusedForAnotherOutcomeOrForestAfterRestart() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        let first = store.current.id
        let completedID = UUID(), skippedID = UUID()
        XCTAssertTrue(store.completeRest(profileID: first, id: completedID, seconds: 20, date: f.start))
        XCTAssertTrue(store.skipRest(profileID: first, id: skippedID, seconds: 20, date: f.start))
        store.createProfile(name: "第二片")
        let second = store.current.id

        let restored = f.store()
        for owner in [first, second] {
            for id in [completedID, skippedID] {
                XCTAssertFalse(restored.completeRest(profileID: owner, id: id, seconds: 90))
                XCTAssertFalse(restored.skipRest(profileID: owner, id: id, seconds: 90))
            }
        }
        XCTAssertEqual(restored.events.count, 2)
        XCTAssertEqual(restored.current.completedRests, 0)
        restored.selectProfile(first)
        XCTAssertEqual(restored.current.completedRests, 1)
        XCTAssertEqual(restored.current.totalRestSeconds, 20)
    }

    @MainActor
    func testInvalidTerminalRecordLeavesTheEncodedDatasetAndGrowthUnchanged() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        let before = try store.snapshot()
        let originalBytes = f.defaults.data(forKey: "forestProfiles.v1")
        for seconds in [0.0, -1, .nan, .infinity, 86_401] {
            XCTAssertFalse(store.completeRest(profileID: store.current.id, id: UUID(), seconds: seconds))
            XCTAssertFalse(store.skipRest(profileID: store.current.id, id: UUID(), seconds: seconds))
        }
        XCTAssertFalse(store.completeRest(profileID: UUID(), id: UUID(), seconds: 20))
        XCTAssertFalse(store.skipRest(profileID: UUID(), id: UUID(), seconds: 20))
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20, date: invalidDate))
        XCTAssertFalse(store.skipRest(profileID: store.current.id, id: UUID(), seconds: 20, date: invalidDate))
        XCTAssertEqual(try store.snapshot(), before)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), originalBytes)
        XCTAssertNil(store.latestRestReward)
    }

    @MainActor
    func testReplacementRestoresAllEventsAndGrowthWithoutReplayingRewards() async throws {
        let f = try Fixture(), incoming = try Fixture()
        defer { f.cleanup(); incoming.cleanup() }
        let store = f.store()
        XCTAssertTrue(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20))
        XCTAssertNotNil(store.latestRestReward)

        let source = incoming.store()
        let sourceOwner = source.current.id
        let completedID = UUID(), skippedID = UUID()
        XCTAssertTrue(source.completeRest(profileID: sourceOwner, id: completedID, seconds: 25, date: incoming.start))
        XCTAssertTrue(source.skipRest(profileID: sourceOwner, id: skippedID, seconds: 25, date: incoming.start))
        source.createProfile(name: "恢复时选中的森林")
        let replacement = try source.snapshot()
        try store.replace(with: replacement)

        XCTAssertEqual(try store.snapshot(), replacement)
        XCTAssertEqual(try f.store().snapshot(), replacement)
        XCTAssertNil(store.latestRestReward)
        XCTAssertFalse(store.completeRest(profileID: sourceOwner, id: completedID, seconds: 25))
        XCTAssertFalse(store.completeRest(profileID: sourceOwner, id: skippedID, seconds: 25))
        XCTAssertNil(store.latestRestReward)
        XCTAssertEqual(store.profiles.first(where: { $0.id == sourceOwner })?.completedRests, 1)
    }

    @MainActor
    func testUnreadableAndFutureArchivesRemainUntouchedUntilAnExplicitMutationPreservesThem() async throws {
        for futureVersion in [false, true] {
            let f = try Fixture()
            defer { f.cleanup() }
            let original: Data
            if futureVersion {
                let profile = ForestProfile(name: "未来的森林")
                let archive = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                                recordingStartedAt: f.start)
                var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
                raw["version"] = 99
                original = try JSONSerialization.data(withJSONObject: raw)
            } else { original = Data("not valid JSON".utf8) }
            f.defaults.set(original, forKey: "forestProfiles.v1")
            let store = f.store()
            XCTAssertFalse(store.canSafelyReplace)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(store.rawArchiveData(), original)
            XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), original)
            XCTAssertNil(f.defaults.data(forKey: "forestProfiles.v1.unreadableBackup"))

            store.renameCurrent("新的本机森林")
            XCTAssertTrue(store.canSafelyReplace)
            XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.unreadableBackup"), original)
            XCTAssertEqual(f.store().current.name, "新的本机森林")
            XCTAssertTrue(f.store().events.isEmpty)
        }
    }

    @MainActor
    func testPreservingAnotherUnreadableArchiveDoesNotOverwriteAnEarlierOriginal() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let olderOriginal = Data("older broken original".utf8)
        let newerOriginal = Data("newer broken original".utf8)
        f.defaults.set(olderOriginal, forKey: "forestProfiles.v1.unreadableBackup")
        f.defaults.set(newerOriginal, forKey: "forestProfiles.v1")
        f.store().renameCurrent("重建")
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1.unreadableBackup"), olderOriginal)
        let copies = f.defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("forestProfiles.v1.unreadableBackup.")
        }
        XCTAssertTrue(copies.values.contains(where: { ($0 as? Data) == newerOriginal }))
        XCTAssertEqual(f.store().current.name, "重建")
    }

    @MainActor
    func testClockMovingBackwardsDoesNotDiscardAValidNewEventOrChangeTheMigrationBaseline() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        let earlier = f.start.addingTimeInterval(-100)
        XCTAssertTrue(store.skipRest(profileID: store.current.id, id: UUID(), seconds: 20, date: earlier))
        XCTAssertEqual(store.events.first?.occurredAt, earlier)
        XCTAssertEqual(store.recordingStartedAt, f.start)
        XCTAssertEqual(f.store().events, store.events)
    }

    @MainActor
    func testAutomaticTerminalEventsCannotReplaceAnUnreadableOriginalWithFallbackProgress() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let original = Data("original bytes awaiting recovery".utf8)
        f.defaults.set(original, forKey: "forestProfiles.v1")
        let store = f.store()
        let before = try store.snapshot()
        XCTAssertFalse(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20))
        XCTAssertFalse(store.skipRest(profileID: store.current.id, id: UUID(), seconds: 20))
        XCTAssertFalse(store.canSafelyReplace)
        XCTAssertEqual(try store.snapshot(), before)
        XCTAssertEqual(store.rawArchiveData(), original)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), original)
        XCTAssertNil(f.defaults.data(forKey: "forestProfiles.v1.unreadableBackup"))
        XCTAssertNil(store.latestRestReward)
    }

    @MainActor
    func testRestoringRawOriginalPreservesItsBytesAndNeverReplaysAnEventOrReward() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        XCTAssertTrue(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20, date: f.start))
        XCTAssertNotNil(store.latestRestReward)
        let raw = Data([0, 255, 128, 14, 0])
        try store.restoreUnreadableOriginal(raw)
        XCTAssertFalse(store.canSafelyReplace)
        XCTAssertEqual(store.rawArchiveData(), raw)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), raw)
        XCTAssertEqual(store.current.completedRests, 0)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNil(store.latestRestReward)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(f.store().rawArchiveData(), raw)
        XCTAssertFalse(f.store().canSafelyReplace)
        XCTAssertFalse(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20))
        XCTAssertEqual(store.rawArchiveData(), raw)
    }

    @MainActor
    func testReadableV1AndV2ArchivesCannotBypassValidationThroughRawRestoration() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let store = f.store()
        let original = try store.snapshot()
        let rawBefore = f.defaults.data(forKey: "forestProfiles.v1")
        let v1 = try JSONEncoder().encode(LegacyArchive(profiles: original.profiles,
                                                       activeProfileID: original.activeProfileID))
        let v2 = try JSONEncoder().encode(original)
        for data in [v1, v2] {
            XCTAssertThrowsError(try store.restoreUnreadableOriginal(data))
            XCTAssertEqual(try store.snapshot(), original)
            XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), rawBefore)
            XCTAssertTrue(store.canSafelyReplace)
        }
    }
}
