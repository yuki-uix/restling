import Foundation
import XCTest
@testable import PomodoroCore

final class ForestSpeciesExpansionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func profile(after count: Int) -> ForestProfile {
        var profile = ForestProfile(name: "保留下来的森林")
        for _ in 0..<count { XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20, date: date)) }
        return profile
    }

    func testOriginalSpeciesIdentityAndUnlocksStayUnchanged() throws {
        let original: [(ForestSpecies, String, Int)] = [(.oak, "oak", 0), (.pine, "pine", 3), (.blossom, "blossom", 6)]
        for (species, rawValue, threshold) in original {
            XCTAssertEqual(species.rawValue, rawValue)
            XCTAssertEqual(species.unlockAfter, threshold)
            XCTAssertEqual(try JSONDecoder().decode(ForestSpecies.self,
                from: Data("\"\(rawValue)\"".utf8)), species)
        }
        XCTAssertEqual(Array(ForestSpecies.allCases.prefix(3)), [.oak, .pine, .blossom])
    }

    func testNewSpeciesUnlockOnlyAtTheirCumulativeThresholds() {
        for (species, count) in [(ForestSpecies.birch, 12), (.willow, 36), (.ginkgo, 72)] {
            XCTAssertEqual(species.unlockAfter, count)
            XCTAssertFalse(profile(after: count - 1).isUnlocked(species))
            let reached = profile(after: count)
            XCTAssertTrue(reached.isUnlocked(species))
            XCTAssertEqual(reached.trees.count, count / 3)
            XCTAssertTrue(reached.trees.allSatisfy { $0.species == .oak },
                          "Unlocking a species must not recolor existing trees.")
        }
    }

    func testLockedNewSelectionsCannotCreateLockedTrees() throws {
        for species in [ForestSpecies.birch, .willow, .ginkgo] {
            var value = profile(after: 0)
            value.selectedSpecies = species
            for _ in 0..<3 { XCTAssertTrue(value.recordRest(id: UUID(), seconds: 20, date: date)) }
            XCTAssertEqual(value.trees.map(\.species), [.oak])
            let roundTrip = try JSONDecoder().decode(ForestProfile.self, from: JSONEncoder().encode(value))
            XCTAssertEqual(roundTrip.selectedSpecies, .oak)
        }
    }

    func testChoosingEachNewSpeciesMidCyclePreservesGrowthAndEstablishedTreeIdentity() {
        for species in [ForestSpecies.birch, .willow, .ginkgo] {
            var value = profile(after: species.unlockAfter + 1)
            let before = value
            XCTAssertEqual(value.growthStage, 1)
            value.selectedSpecies = species
            XCTAssertEqual(value.id, before.id)
            XCTAssertEqual(value.seed, before.seed)
            XCTAssertEqual(value.trees, before.trees)
            XCTAssertEqual(value.completedRests, before.completedRests)
            XCTAssertEqual(value.growthStage, 1)
            for _ in 0..<2 { XCTAssertTrue(value.recordRest(id: UUID(), seconds: 20, date: date)) }
            XCTAssertEqual(Array(value.trees.dropLast()), before.trees)
            XCTAssertEqual(value.trees.last?.species, species)
            XCTAssertEqual(value.completedRests, before.completedRests + 2)
            XCTAssertEqual(value.growthStage, 0)
            XCTAssertEqual(value.restsUntilTree, 3)
        }
    }

    func testAllSpeciesHaveDistinctCatalogueContentAndReadableUnlockStories() {
        XCTAssertEqual(ForestSpecies.allCases.count, 6)
        XCTAssertEqual(Set(ForestSpecies.allCases.map(\.title)).count, 6)
        XCTAssertEqual(Set(ForestSpecies.allCases.map(\.catalogueDescription)).count, 6)
        for species in ForestSpecies.allCases {
            XCTAssertFalse(species.catalogueDescription.isEmpty)
            XCTAssertTrue(species.unlockStory.contains(species.title))
            if species.unlockAfter > 0 { XCTAssertTrue(species.unlockStory.contains("\(species.unlockAfter)")) }
        }
    }

    func testExistingV1ProfilePayloadAndV2BackupRemainCompatible() throws {
        struct LegacyArchive: Codable {
            let version: Int
            let profiles: [ForestProfile]
            let activeProfileID: UUID
        }
        var existing = profile(after: 9)
        existing.selectedSpecies = .blossom
        let legacy = LegacyArchive(version: 1, profiles: [existing], activeProfileID: existing.id)
        let originalData = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(LegacyArchive.self, from: originalData)
        XCTAssertEqual(decoded.profiles, [existing])
        let archive = try ForestArchive(profiles: decoded.profiles, activeProfileID: decoded.activeProfileID,
                                        recordingStartedAt: date)
        XCTAssertEqual(archive.version, 2)
        XCTAssertTrue(archive.events.isEmpty)
        XCTAssertEqual(archive.profiles, [existing])
        let backup = try RestlingBackup(forest: archive, settings: BackupSettings(), createdAt: date)
        let restored = try RestlingBackup.decode(backup.encoded())
        XCTAssertEqual(restored, backup)
        XCTAssertEqual(restored.forest.profiles, [existing])
        XCTAssertTrue(restored.forest.events.isEmpty)
    }

    func testNewSpeciesAndTheirThreeStageCycleSurviveArchiveAndBackupRoundTrips() throws {
        for species in [ForestSpecies.birch, .willow, .ginkgo] {
            var value = profile(after: species.unlockAfter)
            let oldTrees = value.trees
            let seed = value.seed
            value.selectedSpecies = species
            var events: [ForestRestEvent] = []
            for stage in 1...3 {
                let id = UUID()
                let occurredAt = date.addingTimeInterval(Double(stage))
                XCTAssertTrue(value.recordRest(id: id, seconds: 20, date: occurredAt))
                events.append(ForestRestEvent(id: id, profileID: value.id, occurredAt: occurredAt,
                                              configuredSeconds: 20, outcome: .completed))
                XCTAssertEqual(value.growthStage, stage % 3)
                let archive = try ForestArchive(profiles: [value], activeProfileID: value.id,
                                               events: events, recordingStartedAt: date)
                let saved = try JSONDecoder().decode(ForestArchive.self, from: JSONEncoder().encode(archive))
                XCTAssertEqual(saved, archive)
                let backup = try RestlingBackup(forest: saved, settings: BackupSettings(), createdAt: occurredAt)
                XCTAssertEqual(try RestlingBackup.decode(backup.encoded()), backup)
                XCTAssertEqual(saved.profiles[0].selectedSpecies, species)
                XCTAssertEqual(saved.profiles[0].seed, seed)
            }
            XCTAssertEqual(Array(value.trees.dropLast()), oldTrees)
            XCTAssertEqual(value.trees.last?.species, species)
        }
    }
}
