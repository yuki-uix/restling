import Foundation
import XCTest
@testable import PomodoroCore

final class ForestGardenTests: XCTestCase {
    func testNewForestHasOnlyAnUngrownSeed() {
        let profile = ForestProfile(name: "  早晨的小树林 \n")
        XCTAssertEqual(profile.name, "早晨的小树林")
        XCTAssertEqual(profile.selectedSpecies, .oak)
        XCTAssertEqual(profile.completedRests, 0)
        XCTAssertTrue(profile.trees.isEmpty)
        XCTAssertEqual(profile.growthStage, 0)
        XCTAssertEqual(profile.restsUntilTree, 3)
        XCTAssertFalse(profile.isUnlocked(.pine))
    }

    func testThreeRestsGrowATreeAndPreserveTheNextSeed() {
        var profile = ForestProfile(name: "森林")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 300, date: date))
        XCTAssertEqual(profile.growthStage, 1)
        XCTAssertEqual(profile.growthProgress, 1.0 / 3)
        XCTAssertEqual(profile.restsUntilTree, 2)
        XCTAssertTrue(profile.trees.isEmpty)
        XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 300, date: date))
        XCTAssertEqual(profile.growthStage, 2)
        let third = UUID()
        XCTAssertTrue(profile.recordRest(id: third, seconds: 900, date: date))
        XCTAssertEqual(profile.trees.map(\.id), [third])
        XCTAssertEqual(profile.trees.first?.species, .oak)
        XCTAssertEqual(profile.trees.first?.plantedAt, date)
        XCTAssertEqual(profile.totalRestSeconds, 1_500)
        XCTAssertEqual(profile.growthStage, 0)
        XCTAssertEqual(profile.restsUntilTree, 3)
        XCTAssertTrue(profile.isUnlocked(.pine))
        XCTAssertFalse(profile.isUnlocked(.blossom))
        profile.selectedSpecies = .pine
        for _ in 0..<3 { profile.recordRest(id: UUID(), seconds: 300, date: date) }
        XCTAssertEqual(profile.trees.map(\.species), [.oak, .pine])
        XCTAssertTrue(profile.isUnlocked(.blossom))
    }

    func testRewardIDsRemainIdempotentAfterCodableRoundTrip() throws {
        var profile = ForestProfile(name: "森林")
        let restID = UUID()
        XCTAssertTrue(profile.recordRest(id: restID, seconds: 300))
        var restored = try JSONDecoder().decode(ForestProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored, profile)
        XCTAssertFalse(restored.recordRest(id: restID, seconds: 900))
        XCTAssertEqual(restored.completedRests, 1)
        XCTAssertEqual(restored.totalRestSeconds, 300)
        XCTAssertEqual(restored.seed, profile.seed)
    }

    func testInvalidDurationsDoNotGrantProgress() {
        var profile = ForestProfile(name: "森林")
        for seconds in [0.0, -1, .nan, .infinity, -.infinity, 86_401] {
            XCTAssertFalse(profile.recordRest(id: UUID(), seconds: seconds))
        }
        XCTAssertEqual(profile.completedRests, 0)
        XCTAssertEqual(profile.totalRestSeconds, 0)
    }

    func testMalformedLedgerIsRejectedRatherThanCreatingProgress() throws {
        let profile = ForestProfile(name: "森林")
        let encoded = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["completedRests"] = -1
        let malformed = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(ForestProfile.self, from: malformed))
    }
}
