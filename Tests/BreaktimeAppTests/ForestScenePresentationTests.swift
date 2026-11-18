import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class ForestScenePresentationTests: XCTestCase {
    private let monday = Date(timeIntervalSince1970: 1_793_613_600)
    private var nextMonday: Date { monday.addingTimeInterval(7 * 86_400) }

    private func complete(_ count: Int, profile: inout ForestProfile, date: Date) {
        for number in 0..<count {
            XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                date: date.addingTimeInterval(Double(number))))
        }
    }

    func testMigratedForestShowsEmptyCurrentWeekAndKeepsOriginalGrovesWithTheirSeedsAndSlots() {
        var profile = ForestProfile(name: "最初的森林")
        complete(120, profile: &profile, date: monday.addingTimeInterval(-86_400))
        profile.selectedSpecies = .pine
        let oldTrees = profile.trees
        profile.enableWeeklyGrowth(at: monday)
        let current = ForestScenePresentation(profile: profile, selection: .currentWeek, date: monday)
        XCTAssertTrue(current.planted.isEmpty)
        XCTAssertEqual(current.growthStage, 0)
        XCTAssertEqual(current.landscape.completedRests, 0)
        for index in 0..<3 {
            let original = ForestScenePresentation(profile: profile, selection: .legacyGrove(index), date: monday)
            XCTAssertEqual(original.seed, profile.seed &+ UInt64(index) &* 0x9E3779B97F4A7C15)
            XCTAssertEqual(original.planted.map(\.tree), Array(oldTrees.dropFirst(index * 16).prefix(16)))
            XCTAssertEqual(original.planted.map(\.slot), Array(0..<original.planted.count))
            XCTAssertEqual(original.species, .pine)
        }
    }

    func testNewTreesAppearOnlyInTheWeekWhereTheyMaturedAndEachWeekHasAStableDistinctScene() throws {
        var profile = ForestProfile(name: "每周森林")
        profile.enableWeeklyGrowth(at: monday)
        complete(2, profile: &profile, date: monday)
        let firstID = try XCTUnwrap(profile.weeklyJourney?.weeks.first?.id)
        complete(1, profile: &profile, date: nextMonday)
        let secondID = try XCTUnwrap(profile.weeklyJourney?.weeks.last?.id)
        let first = ForestScenePresentation(profile: profile, selection: .week(firstID), date: nextMonday)
        let second = ForestScenePresentation(profile: profile, selection: .week(secondID), date: nextMonday)
        XCTAssertTrue(first.planted.isEmpty)
        XCTAssertEqual(first.growthStage, 2)
        XCTAssertEqual(second.planted.map(\.tree.id), profile.trees.map(\.id))
        XCTAssertEqual(second.planted.count, 1)
        XCTAssertEqual(second.growthStage, 0)
        XCTAssertNotEqual(first.seed, second.seed)
        XCTAssertEqual(first, ForestScenePresentation(profile: profile, selection: .week(firstID), date: nextMonday))
    }

    func testLaterSpeciesChangesAndGrowthCannotRedrawAnArchivedSeedling() throws {
        var profile = ForestProfile(name: "幼苗也被记住")
        profile.enableWeeklyGrowth(at: monday)
        complete(2, profile: &profile, date: monday)
        let firstID = try XCTUnwrap(profile.weeklyJourney?.weeks.first?.id)
        let before = ForestScenePresentation(profile: profile, selection: .week(firstID), date: nextMonday)
        complete(1, profile: &profile, date: nextMonday)
        profile.selectedSpecies = .pine
        complete(24, profile: &profile, date: nextMonday.addingTimeInterval(100))
        let after = ForestScenePresentation(profile: profile, selection: .week(firstID), date: nextMonday)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.species, .oak)
        XCTAssertEqual(after.growthStage, 2)
        XCTAssertTrue(after.planted.isEmpty)
    }

    func testMovingAWeeklyTreeChangesItsSlotWithoutChangingTheLegacySceneOrInventoryOrder() throws {
        var profile = ForestProfile(name: "自己的位置")
        complete(3, profile: &profile, date: monday.addingTimeInterval(-86_400))
        profile.enableWeeklyGrowth(at: monday)
        complete(24, profile: &profile, date: monday)
        let week = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        let treeID = try XCTUnwrap(week.treeIDs.first)
        let inventory = profile.trees
        let original = ForestScenePresentation(profile: profile, selection: .legacyGrove(0), date: monday)
        XCTAssertTrue(profile.moveTree(id: treeID, to: 15, inWeekID: week.id, at: monday))
        let scene = ForestScenePresentation(profile: profile, selection: .week(week.id), date: monday)
        XCTAssertEqual(scene.planted.first?.slot, 15)
        XCTAssertEqual(scene.landscape.landScale, 1)
        XCTAssertEqual(profile.trees, inventory)
        XCTAssertEqual(original, ForestScenePresentation(profile: profile, selection: .legacyGrove(0), date: monday))
    }

    func testEcologicalDiscoveryHasUsableGroundWithoutGrantingEarlyWeeklyScenery() {
        var profile = ForestProfile(name: "池塘来到这一周")
        profile.enableWeeklyGrowth(at: monday)
        complete(1, profile: &profile, date: monday)
        complete(1, profile: &profile, date: nextMonday)
        let thirdWeek = monday.addingTimeInterval(14 * 86_400)
        complete(1, profile: &profile, date: thirdWeek)
        let scene = ForestScenePresentation(profile: profile, selection: .currentWeek, date: thirdWeek)
        XCTAssertEqual(scene.discoveries, [.pond])
        XCTAssertEqual(scene.landscape.landScale, 1)
        XCTAssertEqual(scene.scenery.completedRests, 1)
        XCTAssertFalse(scene.scenery.hasFlowers)
        XCTAssertFalse(scene.scenery.hasStream)
        XCTAssertFalse(scene.scenery.hasMushrooms)
    }

    func testMoreThanSixteenMatureTreesRemainReachableWithoutStartingAnotherWeek() {
        var pending = ForestProfile(name: "十六棵与幼苗")
        pending.enableWeeklyGrowth(at: monday)
        complete(3 + 15 * 24 + 1, profile: &pending, date: monday)
        let cover = ForestScenePresentation(profile: pending, selection: .currentWeek, date: monday, page: 0)
        let seedling = ForestScenePresentation(profile: pending, selection: .currentWeek, date: monday, page: 1)
        XCTAssertEqual(cover.pageCount, 2)
        XCTAssertEqual(cover.planted.count, 16)
        XCTAssertTrue(seedling.planted.isEmpty)
        XCTAssertEqual(seedling.growthStage, 1)
        var profile = ForestProfile(name: "容量边界")
        profile.enableWeeklyGrowth(at: monday)
        complete(3 + 16 * 24, profile: &profile, date: monday)
        XCTAssertEqual(profile.weeklyJourney?.weeks.count, 1)
        let first = ForestScenePresentation(profile: profile, selection: .currentWeek, date: monday, page: 0)
        let second = ForestScenePresentation(profile: profile, selection: .currentWeek, date: monday, page: 1)
        XCTAssertEqual(first.pageCount, 2)
        XCTAssertEqual(first.planted.count, 16)
        XCTAssertEqual(second.planted.count, 1)
        XCTAssertEqual(Set((first.planted + second.planted).map(\.tree.id)), Set(profile.trees.map(\.id)))
    }

    func testEncountersStayOnTheirOwnWeeksFirstPageAndBrowsingNeverRerolls() throws {
        var profile = ForestProfile(name: "林间偶遇")
        profile.enableWeeklyGrowth(at: monday)
        for day in 0..<3 {
            complete(1, profile: &profile, date: monday.addingTimeInterval(Double(day * 86_400)))
        }
        complete(16 * 24, profile: &profile, date: monday.addingTimeInterval(2 * 86_400 + 60))
        let week = try XCTUnwrap(profile.weeklyJourney?.weeks.first)
        XCTAssertFalse(week.encounters.isEmpty)
        let before = profile
        let first = ForestScenePresentation(profile: profile, selection: .week(week.id), date: nextMonday, page: 0)
        let second = ForestScenePresentation(profile: profile, selection: .week(week.id), date: nextMonday, page: 1)
        XCTAssertEqual(first.encounters, week.encounters.compactMap(\.kind))
        XCTAssertTrue(second.encounters.isEmpty)
        XCTAssertTrue(ForestScenePresentation(profile: profile, selection: .currentWeek, date: nextMonday).encounters.isEmpty)
        XCTAssertTrue(ForestScenePresentation(profile: profile, selection: .legacyGrove(0), date: nextMonday).encounters.isEmpty)
        XCTAssertEqual(first, ForestScenePresentation(profile: profile, selection: .week(week.id), date: nextMonday, page: 0))
        XCTAssertEqual(profile, before)
    }
}
