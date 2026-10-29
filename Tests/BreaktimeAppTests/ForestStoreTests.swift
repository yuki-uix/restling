import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ForestStoreTests: XCTestCase {
    @MainActor
    func testChangingCurrentTreeKeepsGrowthAndExistingTrees() async throws {
        let suite = "ForestStoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ForestStore(defaults: defaults)
        for _ in 0..<5 {
            store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20)
        }
        let oldTrees = store.current.trees
        store.selectSpecies(.pine)
        XCTAssertEqual(store.current.completedRests, 5)
        XCTAssertEqual(store.current.growthStage, 2)
        XCTAssertEqual(store.current.restsUntilTree, 1)
        XCTAssertEqual(store.current.totalRestSeconds, 100)
        XCTAssertEqual(store.current.trees, oldTrees)
        XCTAssertEqual(store.current.selectedSpecies, .pine)
        store.completeRest(profileID: store.current.id, id: UUID(), seconds: 20)
        XCTAssertEqual(store.current.trees.first, oldTrees.first)
        XCTAssertEqual(store.current.trees.last?.species, .pine)
        XCTAssertEqual(store.current.trees.count, 2)
        XCTAssertEqual(ForestStore(defaults: defaults).current, store.current)
    }

    @MainActor
    func testProfilesPersistAndRewardsRemainWithTheirOriginalOwner() async throws {
        let suite = "ForestStoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ForestStore(defaults: defaults)
        let firstID = store.current.id
        let seed = store.current.seed
        store.renameCurrent("窗边的森林")
        store.createProfile(name: "午后")
        let secondID = store.current.id
        let restID = UUID()
        XCTAssertTrue(store.completeRest(profileID: firstID, id: restID, seconds: 300))
        XCTAssertEqual(store.current.completedRests, 0)
        store.selectProfile(firstID)
        XCTAssertEqual(store.current.completedRests, 1)
        XCTAssertEqual(store.current.name, "窗边的森林")
        let restored = ForestStore(defaults: defaults)
        XCTAssertEqual(restored.current.id, firstID)
        XCTAssertEqual(restored.current.seed, seed)
        XCTAssertEqual(restored.current.completedRests, 1)
        XCTAssertFalse(restored.completeRest(profileID: firstID, id: restID, seconds: 300))
        restored.selectProfile(secondID)
        XCTAssertEqual(restored.current.name, "午后")
        XCTAssertEqual(restored.current.completedRests, 0)
    }

    @MainActor
    func testLockedSpeciesCannotBeSelectedAndUnlockPersists() async throws {
        let suite = "ForestStoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ForestStore(defaults: defaults)
        store.selectSpecies(.pine)
        XCTAssertEqual(store.current.selectedSpecies, .oak)
        for _ in 0..<3 {
            XCTAssertTrue(store.completeRest(profileID: store.current.id, id: UUID(), seconds: 300))
        }
        store.selectSpecies(.pine)
        XCTAssertEqual(store.current.selectedSpecies, .pine)
        XCTAssertEqual(ForestStore(defaults: defaults).current.selectedSpecies, .pine)
        store.selectProfile(UUID())
        XCTAssertEqual(store.profiles.count, 1)
    }

    @MainActor
    func testCorruptedSaveIsKeptBeforeReplacingIt() async throws {
        let suite = "ForestStoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("not valid JSON".utf8)
        defaults.set(corrupt, forKey: "forestProfiles.v1")
        let store = ForestStore(defaults: defaults)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "forestProfiles.v1"), corrupt)
        XCTAssertEqual(store.current.completedRests, 0)
        store.renameCurrent("重新种一片森林")
        XCTAssertEqual(defaults.data(forKey: "forestProfiles.v1.unreadableBackup"), corrupt)
        XCTAssertEqual(ForestStore(defaults: defaults).current.name, "重新种一片森林")
    }
}
