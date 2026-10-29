import XCTest
@testable import PomodoroCore

final class ForestLandscapeTests: XCTestCase {
    func testNewForestIsBareAndHasNoFreePlantsOrTrees() {
        let landscape = ForestLandscape(profile: ForestProfile(name: "新森林"))
        XCTAssertEqual(landscape.completedRests, 0)
        XCTAssertEqual(landscape.expansionLevel, 0)
        XCTAssertEqual(landscape.expansionProgress, 0)
        XCTAssertFalse(landscape.hasVegetation)
        XCTAssertFalse(landscape.hasCurrentPlant)
        XCTAssertFalse(landscape.hasFlowers)
        XCTAssertFalse(landscape.hasStream)
        XCTAssertFalse(landscape.hasMushrooms)
        XCTAssertEqual(landscape.earnedTreeCount, 0)
        XCTAssertEqual(landscape.visibleTreeCount, 0)
        XCTAssertEqual(landscape.nextExpansionAt, 1)
    }

    func testACompletedTreeDoesNotManufactureANextSeedling() {
        for count in 0...48 {
            let landscape = ForestLandscape(completedRests: count)
            XCTAssertEqual(landscape.hasCurrentPlant, count % 3 != 0)
            XCTAssertEqual(landscape.earnedTreeCount, count / 3)
            XCTAssertEqual(landscape.visibleTreeCount, min(16, count / 3))
        }
    }

    func testLandscapeUnlocksOnlyAtEarnedRestMilestones() {
        XCTAssertFalse(ForestLandscape(completedRests: 5).hasFlowers)
        XCTAssertTrue(ForestLandscape(completedRests: 6).hasFlowers)
        XCTAssertFalse(ForestLandscape(completedRests: 11).hasStream)
        XCTAssertTrue(ForestLandscape(completedRests: 12).hasStream)
        XCTAssertFalse(ForestLandscape(completedRests: 23).hasMushrooms)
        XCTAssertTrue(ForestLandscape(completedRests: 24).hasMushrooms)
        XCTAssertEqual([0, 1, 3, 6, 12, 24].map { ForestLandscape(completedRests: $0).expansionLevel },
                       [0, 1, 2, 3, 4, 5])
        XCTAssertEqual([0, 1, 3, 6, 12, 24].map { ForestLandscape(completedRests: $0).nextExpansionAt },
                       [1, 3, 6, 12, 24, nil])
    }

    func testLandGrowsMonotonicallyAndKeepsValidBounds() {
        var previous = ForestLandscape(completedRests: -10)
        XCTAssertEqual(previous.completedRests, 0)
        for count in 0...100 {
            let current = ForestLandscape(completedRests: count)
            XCTAssertGreaterThanOrEqual(current.landScale, previous.landScale)
            XCTAssertTrue((0...1).contains(current.expansionProgress))
            XCTAssertTrue((0...1).contains(current.landScale))
            previous = current
        }
        XCTAssertEqual(ForestLandscape(completedRests: .max).expansionProgress, 1)
        XCTAssertEqual(ForestLandscape(completedRests: .max).visibleTreeCount, 16)
    }

    func testGrovesContinueAt48RestBoundariesWithoutLosingEarlierLand() {
        let expectations: [(rests: Int, current: Int, count: Int, local: Int)] = [
            (0, 0, 1, 0), (1, 0, 1, 1), (47, 0, 1, 47), (48, 0, 1, 48),
            (49, 1, 2, 1), (95, 1, 2, 47), (96, 1, 2, 48), (97, 2, 3, 1)
        ]
        for expected in expectations {
            let total = ForestLandscape(completedRests: expected.rests)
            XCTAssertEqual(total.currentGroveIndex, expected.current)
            XCTAssertEqual(total.groveCount, expected.count)
            XCTAssertEqual(total.rests(inGrove: expected.current), expected.local)
            let local = ForestLandscape(completedRests: total.rests(inGrove: expected.current))
            XCTAssertEqual(local.visibleTreeCount, expected.local / 3)
            XCTAssertEqual(local.hasCurrentPlant, expected.local % 3 != 0)
            if expected.current > 0 {
                let previous = ForestLandscape(completedRests: total.rests(inGrove: expected.current - 1))
                XCTAssertEqual(previous.completedRests, 48)
                XCTAssertEqual(previous.visibleTreeCount, 16)
                XCTAssertFalse(previous.hasCurrentPlant)
            }
        }
    }

    func testGroveSelectionRejectsInvalidIndicesBeforeArithmetic() {
        let empty = ForestLandscape(completedRests: -1)
        XCTAssertEqual(empty.currentGroveIndex, 0)
        XCTAssertEqual(empty.groveCount, 1)
        let total = ForestLandscape(completedRests: .max)
        for index in [Int.min, -1, total.groveCount, Int.max] {
            XCTAssertEqual(total.rests(inGrove: index), 0)
        }
        XCTAssertEqual(total.rests(inGrove: 0), 48)
        XCTAssertTrue((1...48).contains(total.rests(inGrove: total.currentGroveIndex)))
        // No rest can disappear or be duplicated when partitioned into groves.
        XCTAssertEqual((0..<total.groveCount).reduce(0) { $0 + total.rests(inGrove: $1) }, total.completedRests)
    }
}
