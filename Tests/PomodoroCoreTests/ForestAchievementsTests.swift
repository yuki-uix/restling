import Foundation
import XCTest
@testable import PomodoroCore

final class ForestAchievementsTests: XCTestCase {
    private func profile(rests: Int, seconds: TimeInterval = 20) -> ForestProfile {
        var result = ForestProfile(name: "慢慢生长")
        for index in 0..<rests {
            XCTAssertTrue(result.recordRest(id: UUID(), seconds: seconds,
                date: Date(timeIntervalSince1970: Double(index))))
        }
        return result
    }

    private func profileWithEverySpecies() -> ForestProfile {
        var result = profile(rests: 72, seconds: 180)
        for species in ForestSpecies.allCases {
            result.selectedSpecies = species
            for _ in 0..<3 { XCTAssertTrue(result.recordRest(id: UUID(), seconds: 180)) }
        }
        for _ in 0..<30 { XCTAssertTrue(result.recordRest(id: UUID(), seconds: 180)) }
        return result
    }

    func testCatalogueHasEighteenStableIdentitiesAndFiveNonemptyGroups() {
        let achievements = ForestAchievements(profile: profile(rests: 0))
        XCTAssertEqual(ForestAchievement.allCases.map(\.rawValue), [
            "firstRest", "firstTree", "flowerPath", "stream", "mushrooms", "fullGrove",
            "newGrove", "thirdGrove", "hundredRests", "twoSpecies", "fourSpecies", "sixSpecies",
            "pond", "bridge", "visitors", "tenMinutes", "oneHour", "threeHours"
        ])
        XCTAssertEqual(Set(achievements.items.map(\.id)).count, 18)
        XCTAssertEqual(achievements.totalCount, 18)
        XCTAssertEqual(achievements.unlockedCount, 0)
        XCTAssertEqual(achievements.nextAchievement?.achievement, .firstRest)
        XCTAssertEqual(ForestAchievementCategory.allCases.map { achievements.items(in: $0).count }, [4, 5, 3, 3, 3])
        for category in ForestAchievementCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.subtitle.isEmpty)
        }
        for achievement in ForestAchievement.allCases {
            XCTAssertEqual(achievement.id, achievement.rawValue)
            XCTAssertFalse(achievement.title.isEmpty)
            XCTAssertFalse(achievement.story.isEmpty)
            XCTAssertFalse(achievement.requirement.isEmpty)
            XCTAssertFalse(achievement.symbol.isEmpty)
            XCTAssertEqual(achievements.progress(for: achievement).fraction, 0)
        }
    }

    func testCumulativeMilestonesUnlockExactlyAtTheirExistingRestBoundaries() {
        let thresholds: [(ForestAchievement, Int)] = [
            (.firstRest, 1), (.firstTree, 3), (.flowerPath, 6), (.stream, 12),
            (.mushrooms, 24), (.fullGrove, 48), (.newGrove, 49), (.thirdGrove, 97),
            (.hundredRests, 100), (.pond, 36), (.bridge, 72), (.visitors, 120)
        ]
        for (achievement, threshold) in thresholds {
            let before = ForestAchievements(profile: profile(rests: threshold - 1)).progress(for: achievement)
            let reached = ForestAchievements(profile: profile(rests: threshold)).progress(for: achievement)
            let after = ForestAchievements(profile: profile(rests: threshold + 1)).progress(for: achievement)
            XCTAssertFalse(before.isUnlocked, achievement.rawValue)
            XCTAssertEqual(before.current, Double(threshold - 1))
            XCTAssertEqual(before.target, Double(threshold))
            XCTAssertTrue(reached.isUnlocked, achievement.rawValue)
            XCTAssertTrue(after.isUnlocked, achievement.rawValue)
            XCTAssertEqual(reached.fraction, 1)
            XCTAssertEqual(after.fraction, 1)
            XCTAssertEqual(after.progressText, reached.progressText)
        }
    }

    func testGroveAchievementsDistinguishFillingLandFromOpeningNextLand() {
        for (rests, groveCount, filled, second, third) in [
            (47, 1, false, false, false), (48, 1, true, false, false),
            (49, 2, true, true, false), (96, 2, true, true, false),
            (97, 3, true, true, true)
        ] {
            let forest = profile(rests: rests)
            let achievements = ForestAchievements(profile: forest)
            XCTAssertEqual(ForestLandscape(profile: forest).groveCount, groveCount)
            XCTAssertEqual(achievements.progress(for: .fullGrove).isUnlocked, filled)
            XCTAssertEqual(achievements.progress(for: .newGrove).isUnlocked, second)
            XCTAssertEqual(achievements.progress(for: .thirdGrove).isUnlocked, third)
        }
    }

    func testEcologyAchievementTargetsMatchTheActualSceneryMilestones() {
        for (achievement, milestone) in [(ForestAchievement.pond, ForestEcologyMilestone.pond),
                                        (.bridge, .bridge), (.visitors, .visitors)] {
            for count in [milestone.unlockAfter - 1, milestone.unlockAfter, 145] {
                let forest = profile(rests: count)
                let item = ForestAchievements(profile: forest).progress(for: achievement)
                XCTAssertEqual(item.target, Double(milestone.unlockAfter))
                XCTAssertEqual(item.isUnlocked, ForestEcology(profile: forest).isUnlocked(milestone))
            }
        }
    }

    func testSpeciesAchievementsRequireActuallyMatureTreesNotUnlockedOrSelectedSpecies() {
        var forest = profile(rests: 72)
        XCTAssertTrue(ForestSpecies.allCases.allSatisfy(forest.isUnlocked))
        var achievements = ForestAchievements(profile: forest)
        XCTAssertEqual(achievements.progress(for: .twoSpecies).current, 1)
        XCTAssertFalse(achievements.progress(for: .twoSpecies).isUnlocked)

        forest.selectedSpecies = .pine
        for _ in 0..<2 { XCTAssertTrue(forest.recordRest(id: UUID(), seconds: 20)) }
        achievements = ForestAchievements(profile: forest)
        XCTAssertEqual(achievements.progress(for: .twoSpecies).current, 1)
        XCTAssertFalse(achievements.progress(for: .twoSpecies).isUnlocked)
        XCTAssertTrue(forest.recordRest(id: UUID(), seconds: 20))
        achievements = ForestAchievements(profile: forest)
        XCTAssertTrue(achievements.progress(for: .twoSpecies).isUnlocked)
        XCTAssertEqual(achievements.progress(for: .twoSpecies).current, 2)

        for (index, species) in [ForestSpecies.blossom, .birch, .willow, .ginkgo].enumerated() {
            forest.selectedSpecies = species
            for _ in 0..<3 { XCTAssertTrue(forest.recordRest(id: UUID(), seconds: 20)) }
            achievements = ForestAchievements(profile: forest)
            XCTAssertEqual(achievements.progress(for: .sixSpecies).current, Double(index + 3))
            XCTAssertEqual(achievements.progress(for: .fourSpecies).isUnlocked, index >= 1)
            XCTAssertEqual(achievements.progress(for: .sixSpecies).isUnlocked, index == 3)
        }
        XCTAssertEqual(achievements.progress(for: .sixSpecies).progressText, "6 / 6 种成熟树")
    }

    func testTimeAchievementsUseActualCumulativeSecondsIncludingCustomDurations() {
        let short = ForestAchievements(profile: profile(rests: 100, seconds: 5))
        XCTAssertTrue(short.progress(for: .hundredRests).isUnlocked)
        XCTAssertEqual(short.progress(for: .tenMinutes).current, 500)
        XCTAssertFalse(short.progress(for: .tenMinutes).isUnlocked)
        XCTAssertFalse(short.progress(for: .oneHour).isUnlocked)
        let longer = ForestAchievements(profile: profile(rests: 20, seconds: 180))
        XCTAssertTrue(longer.progress(for: .oneHour).isUnlocked)
        XCTAssertFalse(longer.progress(for: .hundredRests).isUnlocked)

        for (achievement, target) in [(ForestAchievement.tenMinutes, 600.0), (.oneHour, 3_600), (.threeHours, 10_800)] {
            XCTAssertFalse(ForestAchievements(profile: profile(rests: 1, seconds: target - 0.1))
                .progress(for: achievement).isUnlocked)
            XCTAssertTrue(ForestAchievements(profile: profile(rests: 1, seconds: target))
                .progress(for: achievement).isUnlocked)
        }
    }

    func testTimeProgressNeverRoundsAnIncompleteThresholdUp() {
        let pending = ForestAchievements(profile: profile(rests: 1, seconds: 599.9)).progress(for: .tenMinutes)
        XCTAssertEqual(pending.progressText, "9 分 59 秒 / 10 分")
        XCTAssertLessThan(pending.fraction, 1)
        XCTAssertFalse(pending.isUnlocked)
        XCTAssertEqual(ForestAchievements(profile: profile(rests: 1, seconds: 200))
            .progress(for: .oneHour).progressText, "3 分 20 秒 / 1 小时")
        XCTAssertEqual(ForestAchievements(profile: profile(rests: 0))
            .progress(for: .threeHours).progressText, "0 秒 / 3 小时")
        XCTAssertEqual(ForestAchievements(profile: profile(rests: 1, seconds: 86_400))
            .progress(for: .threeHours).progressText, "3 小时 / 3 小时")
    }

    func testNearestMilestoneIsStableAndExcludesAlreadyUnlockedItems() {
        let empty = ForestAchievements(profile: profile(rests: 0))
        XCTAssertEqual(empty.nextAchievement?.achievement, .firstRest)
        let two = ForestAchievements(profile: profile(rests: 2))
        XCTAssertEqual(two.nextAchievement?.achievement, .firstTree)
        let fortySeven = ForestAchievements(profile: profile(rests: 47))
        XCTAssertEqual(fortySeven.nextAchievement?.achievement, .fullGrove)
        let ninetySix = ForestAchievements(profile: profile(rests: 96))
        XCTAssertEqual(ninetySix.nextAchievement?.achievement, .thirdGrove)
        for _ in 0..<20 {
            XCTAssertEqual(ForestAchievements(profile: profile(rests: 47)).nextAchievement?.achievement,
                           fortySeven.nextAchievement?.achievement)
        }
    }

    func testAllAchievementsCanBeCompletedAndFurtherProgressStaysBounded() {
        var forest = profileWithEverySpecies()
        let achievements = ForestAchievements(profile: forest)
        XCTAssertEqual(forest.completedRests, 120)
        XCTAssertEqual(achievements.unlockedCount, 18)
        XCTAssertNil(achievements.nextAchievement)
        XCTAssertTrue(achievements.items.allSatisfy { $0.fraction == 1 && $0.isUnlocked })
        for _ in 0..<100 { XCTAssertTrue(forest.recordRest(id: UUID(), seconds: 86_400)) }
        let later = ForestAchievements(profile: forest)
        XCTAssertEqual(later.items.map(\.progressText), achievements.items.map(\.progressText))
        XCTAssertTrue(later.items.allSatisfy { $0.fraction.isFinite && (0...1).contains($0.fraction) })
    }

    func testDerivationPreservesTheWholeProfileAndSurvivesItsRoundTrip() throws {
        let forest = profileWithEverySpecies()
        let original = forest
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(forest)
        let achievements = ForestAchievements(profile: forest)
        for _ in 0..<100 {
            XCTAssertEqual(ForestAchievements(profile: forest), achievements)
            for item in achievements.items {
                _ = item.achievement.story
                _ = item.progressText
            }
        }
        XCTAssertEqual(forest, original)
        XCTAssertEqual(try encoder.encode(forest), bytes)
        let restored = try JSONDecoder().decode(ForestProfile.self, from: bytes)
        XCTAssertEqual(ForestAchievements(profile: restored), achievements)
    }
}
