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

    func testCatalogueKeepsEighteenIdentitiesAndAddsFourLongTermFootprints() {
        let achievements = ForestAchievements(profile: profile(rests: 0))
        XCTAssertEqual(ForestAchievement.allCases.map(\.rawValue), [
            "firstRest", "firstTree", "flowerPath", "stream", "mushrooms", "fullGrove",
            "newGrove", "thirdGrove", "hundredRests", "twoSpecies", "fourSpecies", "sixSpecies",
            "pond", "bridge", "visitors", "tenMinutes", "oneHour", "threeHours",
            "fourWeeks", "twelveWeeks", "twentySixWeeks", "mixedGrove"
        ])
        XCTAssertEqual(Set(achievements.items.map(\.id)).count, 22)
        XCTAssertEqual(achievements.totalCount, 22)
        XCTAssertEqual(achievements.unlockedCount, 0)
        XCTAssertEqual(achievements.nextAchievement?.achievement, .firstRest)
        XCTAssertEqual(ForestAchievementCategory.allCases.map { achievements.items(in: $0).count }, [4, 8, 4, 3, 3])
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

    func testAllLegacyAchievementsRemainCompletedAndFurtherProgressStaysBounded() {
        var forest = profileWithEverySpecies()
        let achievements = ForestAchievements(profile: forest)
        XCTAssertEqual(forest.completedRests, 120)
        XCTAssertEqual(achievements.unlockedCount, 18)
        XCTAssertEqual(achievements.nextAchievement?.achievement, .fourWeeks)
        XCTAssertTrue(achievements.items.prefix(18).allSatisfy { $0.fraction == 1 && $0.isUnlocked })
        XCTAssertTrue(achievements.items.suffix(4).allSatisfy { !$0.isUnlocked })
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

    private var weeklyCalendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func weeklyDate(_ index: Int) -> Date {
        ISO8601DateFormatter().date(from: "2026-01-05T12:00:00Z")!
            .addingTimeInterval(Double(index * 14) * 86_400)
    }

    private func weeklyProfile(legacyRests: Int = 0) -> ForestProfile {
        var result = profile(rests: legacyRests)
        XCTAssertTrue(result.enableWeeklyGrowth(at: weeklyDate(0), calendar: weeklyCalendar))
        return result
    }

    private func complete(_ count: Int, inWeek index: Int, profile: inout ForestProfile,
                          seconds: TimeInterval = 20) {
        for _ in 0..<count {
            XCTAssertTrue(profile.recordRest(id: UUID(), seconds: seconds,
                date: weeklyDate(index), calendar: weeklyCalendar))
        }
    }

    func testMigrationPreservesEveryAlreadyEarnedLegacyFootprintWithoutCreatingWeeks() {
        var forest = profileWithEverySpecies()
        let before = ForestAchievements(profile: forest)
        XCTAssertEqual(before.unlockedCount, 18)
        let trees = forest.trees
        XCTAssertTrue(forest.enableWeeklyGrowth(at: weeklyDate(0), calendar: weeklyCalendar))
        let migrated = ForestAchievements(profile: forest)
        XCTAssertEqual(migrated.unlockedCount, 18)
        XCTAssertEqual(migrated.items.prefix(18).map(\.isUnlocked), before.items.prefix(18).map(\.isUnlocked))
        XCTAssertEqual(forest.trees, trees)
        XCTAssertTrue(forest.weeklyJourney!.weeks.isEmpty)
        for item in migrated.items where item.isLegacyRecognition {
            XCTAssertTrue(item.requirement.contains("旧版"))
            XCTAssertTrue(item.progressText.contains("已保留"))
            XCTAssertEqual(item.fraction, 1)
        }
        XCTAssertTrue(migrated.progress(for: .fullGrove).isLegacyRecognition)
        XCTAssertTrue(migrated.progress(for: .pond).isLegacyRecognition)
        XCTAssertFalse(migrated.progress(for: .fourWeeks).isUnlocked)
    }

    func testWeeklyLandFootprintsCountRecordedWeeksInsteadOfCumulativeFortyNineRests() {
        var forest = weeklyProfile()
        complete(100, inWeek: 0, profile: &forest)
        var achievements = ForestAchievements(profile: forest)
        XCTAssertFalse(achievements.progress(for: .newGrove).isUnlocked)
        XCTAssertEqual(achievements.progress(for: .newGrove).current, 1)
        XCTAssertEqual(achievements.progress(for: .newGrove).target, 2)
        XCTAssertTrue(achievements.progress(for: .fullGrove).isUnlocked)
        XCTAssertEqual(achievements.progress(for: .fullGrove).target, 4)
        XCTAssertEqual(achievements.progress(for: .fullGrove).current, Double(forest.trees.count))
        complete(1, inWeek: 3, profile: &forest)
        achievements = ForestAchievements(profile: forest)
        XCTAssertTrue(achievements.progress(for: .newGrove).isUnlocked)
        XCTAssertFalse(achievements.progress(for: .thirdGrove).isUnlocked)
        complete(1, inWeek: 8, profile: &forest)
        XCTAssertTrue(ForestAchievements(profile: forest).progress(for: .thirdGrove).isUnlocked)
    }

    func testWeeklySmallGroveUnlocksAtFourMatureTreesAndSixteenOnlyControlsPaging() {
        var forest = weeklyProfile()
        complete(74, inWeek: 0, profile: &forest)
        let before = ForestAchievements(profile: forest).progress(for: .fullGrove)
        XCTAssertEqual(forest.trees.count, 3)
        XCTAssertEqual(before.current, 3)
        XCTAssertEqual(before.target, 4)
        XCTAssertEqual(before.fraction, 0.75)
        XCTAssertFalse(before.isUnlocked)

        complete(1, inWeek: 0, profile: &forest)
        let earned = ForestAchievements(profile: forest).progress(for: .fullGrove)
        XCTAssertEqual(forest.trees.count, 4)
        XCTAssertTrue(earned.isUnlocked)
        XCTAssertEqual(earned.progressText, "4 / 4 棵成树")
        XCTAssertTrue(earned.requirement.contains("同一周"))
        XCTAssertTrue(earned.requirement.contains("4 棵"))
        XCTAssertFalse(earned.requirement.contains("16"))
        XCTAssertEqual(earned.story, "一周的小停顿，长成了一片小树林。")

        complete(288, inWeek: 0, profile: &forest)
        XCTAssertEqual(forest.trees.count, 16)
        XCTAssertEqual(forest.weeklyJourney?.weeks[0].pageCount, 1)
        XCTAssertEqual(ForestAchievements(profile: forest).progress(for: .fullGrove).target, 4)
        complete(24, inWeek: 0, profile: &forest)
        XCTAssertEqual(forest.trees.count, 17)
        XCTAssertEqual(forest.weeklyJourney?.weeks[0].pageCount, 2)
        let overflow = ForestAchievements(profile: forest).progress(for: .fullGrove)
        XCTAssertTrue(overflow.isUnlocked)
        XCTAssertEqual(overflow.progressText, earned.progressText)
    }

    func testWeeklySmallGroveDoesNotCombineMatureTreesFromDifferentWeeks() {
        var forest = weeklyProfile()
        complete(27, inWeek: 0, profile: &forest)
        complete(48, inWeek: 1, profile: &forest)
        XCTAssertEqual(forest.trees.count, 4)
        let item = ForestAchievements(profile: forest).progress(for: .fullGrove)
        XCTAssertEqual(item.current, 2)
        XCTAssertEqual(item.target, 4)
        XCTAssertFalse(item.isUnlocked)
    }

    func testWeeklySceneryFootprintsRequireSceneryToExistInAnActualWeek() {
        var forest = weeklyProfile()
        for week in 0..<3 { complete(4, inWeek: week, profile: &forest) }
        var achievements = ForestAchievements(profile: forest)
        XCTAssertEqual(forest.completedRests, 12)
        XCTAssertFalse(achievements.progress(for: .flowerPath).isUnlocked)
        XCTAssertFalse(achievements.progress(for: .stream).isUnlocked)
        complete(2, inWeek: 2, profile: &forest)
        achievements = ForestAchievements(profile: forest)
        XCTAssertTrue(achievements.progress(for: .flowerPath).isUnlocked)
        XCTAssertFalse(achievements.progress(for: .stream).isUnlocked)
        complete(6, inWeek: 2, profile: &forest)
        XCTAssertTrue(ForestAchievements(profile: forest).progress(for: .stream).isUnlocked)
    }

    func testFourTwelveAndTwentySixWeeksNeedNoConsecutiveAttendanceAndIgnoreEmptyDisplayWeeks() {
        var forest = weeklyProfile()
        let original = forest
        _ = forest.weeklyJourney!.displayWeek(at: weeklyDate(30), calendar: weeklyCalendar)
        XCTAssertEqual(forest, original)
        XCTAssertEqual(ForestAchievements(profile: forest).progress(for: .fourWeeks).current, 0)
        for index in 0..<26 {
            complete(1, inWeek: index, profile: &forest)
            let achievements = ForestAchievements(profile: forest)
            for (achievement, target) in [(ForestAchievement.fourWeeks, 4), (.twelveWeeks, 12), (.twentySixWeeks, 26)] {
                let item = achievements.progress(for: achievement)
                XCTAssertEqual(item.isUnlocked, index + 1 >= target)
                XCTAssertEqual(item.current, Double(index + 1))
                XCTAssertTrue(item.requirement.contains("无需连续"))
            }
        }
    }

    func testMixedGroveRequiresThreeMatureSpeciesInOneWeekAndIgnoresBrowsingOrSelection() {
        var forest = weeklyProfile()
        complete(3, inWeek: 0, profile: &forest)
        forest.selectedSpecies = .pine
        complete(24, inWeek: 0, profile: &forest)
        forest.selectedSpecies = .blossom
        complete(23, inWeek: 0, profile: &forest)
        var achievements = ForestAchievements(profile: forest)
        XCTAssertTrue(achievements.progress(for: .twoSpecies).isUnlocked)
        XCTAssertFalse(achievements.progress(for: .mixedGrove).isUnlocked)
        XCTAssertEqual(achievements.progress(for: .mixedGrove).current, 2)
        complete(1, inWeek: 1, profile: &forest)
        achievements = ForestAchievements(profile: forest)
        XCTAssertFalse(achievements.progress(for: .mixedGrove).isUnlocked)
        complete(24, inWeek: 1, profile: &forest)
        forest.selectedSpecies = .oak
        complete(24, inWeek: 1, profile: &forest)
        XCTAssertFalse(ForestAchievements(profile: forest).progress(for: .mixedGrove).isUnlocked)
        forest.selectedSpecies = .pine
        complete(24, inWeek: 1, profile: &forest)
        XCTAssertTrue(ForestAchievements(profile: forest).progress(for: .mixedGrove).isUnlocked)
    }

    func testAllTwentyTwoFootprintsCanBeEarnedFromActualWeeklyGrowthAndRoundTrip() throws {
        var forest = weeklyProfile()
        for index in 0..<363 {
            let eligible = ForestSpecies.allCases.filter(forest.isUnlocked)
            forest.selectedSpecies = eligible[(index / 24) % eligible.count]
            complete(1, inWeek: 0, profile: &forest, seconds: 180)
        }
        for week in 1..<26 { complete(1, inWeek: week, profile: &forest, seconds: 180) }
        let achievements = ForestAchievements(profile: forest)
        XCTAssertEqual(achievements.totalCount, 22)
        XCTAssertEqual(achievements.unlockedCount, 22)
        XCTAssertNil(achievements.nextAchievement)
        XCTAssertTrue(achievements.items.allSatisfy { $0.fraction == 1 && $0.isUnlocked })
        let original = forest
        _ = ForestAchievements(profile: forest)
        XCTAssertEqual(forest, original)
        let restored = try JSONDecoder().decode(ForestProfile.self, from: JSONEncoder().encode(forest))
        XCTAssertEqual(ForestAchievements(profile: restored), achievements)
    }
}
