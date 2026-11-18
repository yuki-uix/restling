import Foundation
import XCTest
@testable import PomodoroCore

final class ForestEcologyTests: XCTestCase {
    func testDiscoveriesHaveExplicitCumulativeThresholdsAndPermanentGroves() {
        XCTAssertEqual(ForestEcologyMilestone.allCases.map(\.unlockAfter), [36, 72, 120])
        XCTAssertEqual(ForestEcologyMilestone.allCases.map(\.groveIndex), [0, 1, 2])
        XCTAssertEqual(ForestEcologyMilestone.allCases.map(\.title), ["池塘", "石桥", "林间访客"])
        for milestone in ForestEcologyMilestone.allCases {
            XCTAssertEqual(milestone.id, milestone.rawValue)
            XCTAssertTrue(milestone.teaser.contains("\(milestone.groveIndex + 1)"))
            XCTAssertTrue(milestone.detail.contains("\(milestone.unlockAfter)"))
            XCTAssertTrue(milestone.detail.contains("\(milestone.groveIndex + 1)"))
        }
    }

    func testNewForestsAndInsufficientCountsDoNotReceiveFreeEcology() {
        let fresh = ForestEcology(profile: ForestProfile(name: "空地"))
        XCTAssertEqual(fresh.completedRests, 0)
        XCTAssertTrue(fresh.unlockedMilestones.isEmpty)
        XCTAssertEqual(fresh.nextMilestone, .pond)
        XCTAssertEqual(fresh.restsUntilNext, 36)
        XCTAssertEqual(fresh.progressTowardsNext, 0)
        for count in 0..<36 {
            let ecology = ForestEcology(completedRests: count)
            XCTAssertFalse(ecology.isUnlocked(.pond))
            XCTAssertTrue(ecology.milestones(inGrove: 0).isEmpty)
        }
    }

    func testEachThresholdUnlocksExactlyOneDiscoveryWithoutAClaimStep() {
        for (index, milestone) in ForestEcologyMilestone.allCases.enumerated() {
            let before = ForestEcology(completedRests: milestone.unlockAfter - 1)
            let reached = ForestEcology(completedRests: milestone.unlockAfter)
            let after = ForestEcology(completedRests: milestone.unlockAfter + 1)
            XCTAssertFalse(before.isUnlocked(milestone))
            XCTAssertTrue(reached.isUnlocked(milestone))
            XCTAssertTrue(after.isUnlocked(milestone))
            XCTAssertEqual(before.unlockedMilestones.count, index)
            XCTAssertEqual(reached.unlockedMilestones.count, index + 1)
            XCTAssertEqual(reached.milestones(inGrove: milestone.groveIndex), [milestone])
            XCTAssertEqual(ForestEcology.milestone(at: milestone.unlockAfter), milestone)
            XCTAssertNil(ForestEcology.milestone(at: milestone.unlockAfter - 1))
            XCTAssertNil(ForestEcology.milestone(at: milestone.unlockAfter + 1))
        }
    }

    func testOpeningNewLandAt49And97DoesNotResetGlobalAnticipation() {
        let second = ForestEcology(completedRests: 49)
        XCTAssertEqual(second.nextMilestone, .bridge)
        XCTAssertEqual(second.restsUntilNext, 23)
        XCTAssertEqual(second.progressTowardsNext, 13.0 / 36, accuracy: 1e-12)
        XCTAssertTrue(second.nextMilestoneText.contains("23"))
        XCTAssertTrue(second.nextMilestoneText.contains("第 2 片"))
        XCTAssertEqual(second.milestones(inGrove: 0), [.pond])
        XCTAssertTrue(second.milestones(inGrove: 1).isEmpty)

        let third = ForestEcology(completedRests: 97)
        XCTAssertEqual(third.nextMilestone, .visitors)
        XCTAssertEqual(third.restsUntilNext, 23)
        XCTAssertEqual(third.progressTowardsNext, 25.0 / 48, accuracy: 1e-12)
        XCTAssertTrue(third.nextMilestoneText.contains("第 3 片"))
        XCTAssertEqual(third.milestones(inGrove: 0), [.pond])
        XCTAssertEqual(third.milestones(inGrove: 1), [.bridge])
        XCTAssertTrue(third.milestones(inGrove: 2).isEmpty)
    }

    func testAt145AllDiscoveriesRemainOnTheirOwnEarlierLand() {
        let ecology = ForestEcology(completedRests: 145)
        XCTAssertEqual(ecology.unlockedMilestones, [.pond, .bridge, .visitors])
        XCTAssertEqual(ecology.milestones(inGrove: 0), [.pond])
        XCTAssertEqual(ecology.milestones(inGrove: 1), [.bridge])
        XCTAssertEqual(ecology.milestones(inGrove: 2), [.visitors])
        XCTAssertTrue(ecology.milestones(inGrove: 3).isEmpty)
        XCTAssertNil(ecology.nextMilestone)
        XCTAssertNil(ecology.restsUntilNext)
        XCTAssertEqual(ecology.progressTowardsNext, 1)
        XCTAssertTrue(ecology.nextMilestoneText.contains("三次休息"))
    }

    func testProgressUsesThePreviousDiscoveryAndTheExisting24RestForest() {
        let cases: [(Int, Double)] = [
            (0, 0), (23, 0), (24, 0), (30, 0.5), (35, 11.0 / 12),
            (36, 0), (54, 0.5), (71, 35.0 / 36), (72, 0), (96, 0.5),
            (119, 47.0 / 48), (120, 1), (1_000_000, 1)
        ]
        for (count, progress) in cases {
            XCTAssertEqual(ForestEcology(completedRests: count).progressTowardsNext,
                           progress, accuracy: 1e-12, "Count \(count)")
        }
    }

    func testBoundsAndInvalidGroveIndicesAreSafe() {
        let negative = ForestEcology(completedRests: .min)
        XCTAssertEqual(negative.completedRests, 0)
        XCTAssertEqual(negative.progressTowardsNext, 0)
        let huge = ForestEcology(completedRests: .max)
        XCTAssertEqual(huge.completedRests, 1_000_000)
        XCTAssertEqual(huge.progressTowardsNext, 1)
        for index in [Int.min, -1, Int.max] {
            XCTAssertTrue(huge.milestones(inGrove: index).isEmpty)
        }
        XCTAssertTrue(negative.milestones(inGrove: 1).isEmpty)
        XCTAssertNil(ForestEcology.milestone(at: .min))
        XCTAssertNil(ForestEcology.milestone(at: .max))
    }

    func testDerivedDiscoveriesAreStableAndDoNotMutateTheirProfile() {
        var profile = ForestProfile(name: "一直生长的森林")
        for _ in 0..<145 { XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20)) }
        let original = profile
        let ecology = ForestEcology(profile: profile)
        for _ in 0..<10 {
            XCTAssertEqual(ForestEcology(profile: profile), ecology)
            for grove in 0..<ForestLandscape(profile: profile).groveCount {
                XCTAssertEqual(ecology.milestones(inGrove: grove).count, grove < 3 ? 1 : 0)
            }
        }
        XCTAssertEqual(profile, original)
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
        var profile = ForestProfile(name: "每周森林")
        for _ in 0..<legacyRests { XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20)) }
        XCTAssertTrue(profile.enableWeeklyGrowth(at: weeklyDate(0), calendar: weeklyCalendar))
        return profile
    }

    func testWeeklyDiscoveriesUseThreeSixAndTenRecordedWeeksAndStayAtTheEarningWeek() {
        var profile = weeklyProfile()
        XCTAssertEqual(ForestEcologyMilestone.allCases.map(\.weeklyUnlockAfter), [3, 6, 10])
        for index in 0..<11 {
            XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                date: weeklyDate(index), calendar: weeklyCalendar))
            let ecology = ForestEcology(profile: profile)
            XCTAssertTrue(ecology.isWeekly)
            XCTAssertEqual(ecology.completedWeekCount, index + 1)
            XCTAssertNil(ecology.restsUntilNext)
            for milestone in ForestEcologyMilestone.allCases {
                let unlocked = index + 1 >= milestone.weeklyUnlockAfter
                XCTAssertEqual(ecology.isUnlocked(milestone), unlocked)
                XCTAssertEqual(ecology.target(for: milestone), milestone.weeklyUnlockAfter)
                if unlocked {
                    let targetWeek = profile.weeklyJourney!.weeks[milestone.weeklyUnlockAfter - 1]
                    XCTAssertEqual(ecology.location(for: milestone), .week(targetWeek.id))
                    XCTAssertEqual(ecology.milestones(inWeekID: targetWeek.id), [milestone])
                }
            }
            XCTAssertTrue(ecology.milestones(inGrove: 0).isEmpty)
            XCTAssertTrue(ecology.milestones(inWeekID: "unknown").isEmpty)
        }
        let final = ForestEcology(profile: profile)
        XCTAssertNil(final.nextMilestone)
        XCTAssertNil(final.weeksUntilNext)
        XCTAssertEqual(final.progressTowardsNext, 1)
    }

    func testOpeningEmptyWeeksAndPassingLegacyRestThresholdsCannotUnlockWeeklyEcology() {
        var profile = weeklyProfile(legacyRests: 35)
        let original = profile
        _ = profile.weeklyJourney!.displayWeek(at: weeklyDate(30), calendar: weeklyCalendar)
        XCTAssertEqual(profile, original)
        var ecology = ForestEcology(profile: profile)
        XCTAssertEqual(ecology.completedWeekCount, 0)
        XCTAssertFalse(ecology.isUnlocked(.pond))
        XCTAssertEqual(ecology.weeksUntilNext, 3)
        XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
            date: weeklyDate(0), calendar: weeklyCalendar))
        ecology = ForestEcology(profile: profile)
        XCTAssertEqual(profile.completedRests, 36)
        XCTAssertFalse(ecology.isUnlocked(.pond))
        XCTAssertEqual(ecology.weeksUntilNext, 2)
        XCTAssertTrue(ecology.nextMilestoneText.contains("无需连续"))
    }

    func testMigratedSceneryRemainsInItsOriginalGroveWhileNewDiscoveriesBelongToWeeks() {
        var profile = weeklyProfile(legacyRests: 36)
        XCTAssertEqual(ForestEcology(profile: profile).location(for: .pond), .legacyGrove(0))
        for index in 0..<10 {
            XCTAssertTrue(profile.recordRest(id: UUID(), seconds: 20,
                date: weeklyDate(index), calendar: weeklyCalendar))
        }
        let ecology = ForestEcology(profile: profile)
        XCTAssertEqual(ecology.location(for: .pond), .legacyGrove(0))
        XCTAssertEqual(ecology.milestones(inGrove: 0), [.pond])
        XCTAssertEqual(ecology.location(for: .bridge), .week(profile.weeklyJourney!.weeks[5].id))
        XCTAssertEqual(ecology.location(for: .visitors), .week(profile.weeklyJourney!.weeks[9].id))
        XCTAssertTrue(ecology.requirementText(for: .pond).contains("最初的森林"))
        XCTAssertTrue(ecology.requirementText(for: .bridge).contains("6"))
        XCTAssertTrue(ecology.detail(for: .bridge).contains("保留"))
    }

    func testAllLegacyEcologySurvivesMigrationWithoutNewWeeksOrRediscovery() {
        let profile = weeklyProfile(legacyRests: 145)
        let ecology = ForestEcology(profile: profile)
        XCTAssertEqual(ecology.unlockedMilestones, [.pond, .bridge, .visitors])
        XCTAssertEqual(ecology.completedWeekCount, 0)
        for milestone in ForestEcologyMilestone.allCases {
            XCTAssertEqual(ecology.location(for: milestone), .legacyGrove(milestone.groveIndex))
            XCTAssertEqual(ecology.currentValue(for: milestone), ecology.target(for: milestone))
        }
        XCTAssertTrue(ecology.milestones(inGrove: 3).isEmpty)
        XCTAssertNil(ecology.nextMilestone)
    }
}
