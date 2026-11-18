import Foundation

/// Permanent ecological discoveries use the whole forest's earned rest count.
/// Each discovery belongs to one retained grove, rather than appearing for free
/// on every newly opened piece of bare land.
public enum ForestEcologyMilestone: String, CaseIterable, Identifiable, Sendable {
    case pond, bridge, visitors

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pond: return "池塘"
        case .bridge: return "石桥"
        case .visitors: return "林间访客"
        }
    }

    public var unlockAfter: Int {
        switch self {
        case .pond: return 36
        case .bridge: return 72
        case .visitors: return 120
        }
    }

    /// Distinct weeks with completed rests, never consecutive attendance.
    public var weeklyUnlockAfter: Int {
        switch self {
        case .pond: return 3
        case .bridge: return 6
        case .visitors: return 10
        }
    }

    /// Zero-based viewport index, stable across later forest expansion.
    public var groveIndex: Int {
        switch self {
        case .pond: return 0
        case .bridge: return 1
        case .visitors: return 2
        }
    }

    public var teaser: String {
        switch self {
        case .pond: return "第 1 片林地会留下一汪小池塘。"
        case .bridge: return "第 2 片林地会搭起一座石桥。"
        case .visitors: return "第 3 片林地会迎来小小的林间访客。"
        }
    }

    public var detail: String {
        switch self {
        case .pond:
            return "累计完成 36 次休息，第 1 片林地会多一汪池塘。休息结束后，再回来看看水边的新绿。"
        case .bridge:
            return "累计完成 72 次休息，第 2 片林地的溪流上会出现一座石桥。第 1 片林地的池塘也会一直保留。"
        case .visitors:
            return "累计完成 120 次休息，第 3 片林地会迎来林间访客。休息结束后，回到森林看看它们的身影。"
        }
    }
}

/// Existing discoveries retain their original groves. New discoveries follow
/// recorded weeks and remain in the week that first earned them. This value is
/// read-only: no clocks, streaks, claims or extra rewards are involved.
public enum ForestEcologyLocation: Equatable, Sendable {
    case legacyGrove(Int)
    case week(String)
}

public struct ForestEcology: Equatable, Sendable {
    public let completedRests: Int
    private let legacyCompletedRests: Int
    private let weeks: [ForestWeek]?

    public init(completedRests: Int) {
        self.completedRests = min(1_000_000, max(0, completedRests))
        legacyCompletedRests = self.completedRests
        weeks = nil
    }

    public init(profile: ForestProfile) {
        completedRests = profile.completedRests
        legacyCompletedRests = profile.weeklyJourney?.legacyCompletedRests ?? profile.completedRests
        weeks = profile.weeklyJourney?.weeks
    }

    public var isWeekly: Bool { weeks != nil }
    public var completedWeekCount: Int { weeks?.count ?? 0 }

    public var unlockedMilestones: [ForestEcologyMilestone] {
        ForestEcologyMilestone.allCases.filter(isUnlocked)
    }

    public var nextMilestone: ForestEcologyMilestone? {
        ForestEcologyMilestone.allCases.first { !isUnlocked($0) }
    }

    public var restsUntilNext: Int? {
        guard !isWeekly else { return nil }
        return nextMilestone.map { $0.unlockAfter - completedRests }
    }

    public var weeksUntilNext: Int? {
        guard isWeekly else { return nil }
        return nextMilestone.map { max(0, $0.weeklyUnlockAfter - completedWeekCount) }
    }

    public var progressTowardsNext: Double {
        guard let nextMilestone else { return 1 }
        if isWeekly {
            let previous = unlockedMilestones.last?.weeklyUnlockAfter ?? 0
            let span = nextMilestone.weeklyUnlockAfter - previous
            return min(1, max(0, Double(completedWeekCount - previous) / Double(span)))
        }
        let previous = unlockedMilestones.last?.unlockAfter ?? 24
        let span = nextMilestone.unlockAfter - previous
        return min(1, max(0, Double(completedRests - previous) / Double(span)))
    }

    public func isUnlocked(_ milestone: ForestEcologyMilestone) -> Bool {
        location(for: milestone) != nil
    }

    public func location(for milestone: ForestEcologyMilestone) -> ForestEcologyLocation? {
        if legacyCompletedRests >= milestone.unlockAfter { return .legacyGrove(milestone.groveIndex) }
        guard let weeks, weeks.count >= milestone.weeklyUnlockAfter else { return nil }
        return .week(weeks[milestone.weeklyUnlockAfter - 1].id)
    }

    public func milestones(inGrove index: Int) -> [ForestEcologyMilestone] {
        let currentGrove = ForestLandscape(completedRests: legacyCompletedRests).currentGroveIndex
        guard index >= 0, index <= currentGrove else { return [] }
        return unlockedMilestones.filter { location(for: $0) == .legacyGrove(index) }
    }

    public func milestones(inWeekID id: String) -> [ForestEcologyMilestone] {
        unlockedMilestones.filter { location(for: $0) == .week(id) }
    }

    public func target(for milestone: ForestEcologyMilestone) -> Int {
        isWeekly ? milestone.weeklyUnlockAfter : milestone.unlockAfter
    }

    public func currentValue(for milestone: ForestEcologyMilestone) -> Int {
        if isWeekly, case .legacyGrove? = location(for: milestone) { return target(for: milestone) }
        return min(target(for: milestone), isWeekly ? completedWeekCount : completedRests)
    }

    public func requirementText(for milestone: ForestEcologyMilestone) -> String {
        if isWeekly, case .legacyGrove(let index)? = location(for: milestone) {
            return "最初的森林 · 第 \(index + 1) 片林地，旧版已获得"
        }
        if isWeekly { return "在 \(milestone.weeklyUnlockAfter) 个不同的周完成休息，无需连续。" }
        return "累计完成 \(milestone.unlockAfter) 次休息 · 第 \(milestone.groveIndex + 1) 片林地"
    }

    public func detail(for milestone: ForestEcologyMilestone) -> String {
        if !isWeekly { return milestone.detail }
        if case .legacyGrove? = location(for: milestone) { return milestone.detail }
        if let location = location(for: milestone), case .week = location {
            return "\(milestone.title)已留在第 \(milestone.weeklyUnlockAfter) 个有休息记录的周。它会保留在那一周的森林，随时可以回访。"
        }
        return "第 \(milestone.weeklyUnlockAfter) 个有休息记录的周，会留下\(milestone.title)。休息过的每一周都会积累，中断也不会清零。"
    }

    public var nextMilestoneText: String {
        guard let next = nextMilestone else {
            return isWeekly ? "池塘、石桥与林间访客都已留下。继续培育，每周留下一处风景。" : "池塘、石桥与林间访客都已留下。每三次休息，继续种下一棵树。"
        }
        if isWeekly { return "再留下 \(max(0, next.weeklyUnlockAfter - completedWeekCount)) 个有休息记录的周，森林将迎来\(next.title)。无需连续。" }
        let remaining = next.unlockAfter - completedRests
        return "再完成 \(remaining) 次休息，第 \(next.groveIndex + 1) 片林地将出现\(next.title)。"
    }

    public static func milestone(at completedRests: Int) -> ForestEcologyMilestone? {
        ForestEcologyMilestone.allCases.first { $0.unlockAfter == completedRests }
    }
}
