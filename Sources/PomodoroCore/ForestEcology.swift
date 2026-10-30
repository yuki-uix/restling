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

/// Derived only from cumulative completed rests: no clocks, streaks, claims or
/// extra persistence can take away an earned discovery. Local land growth and
/// the three-rest tree rhythm remain the responsibility of ForestLandscape.
public struct ForestEcology: Equatable, Sendable {
    public let completedRests: Int

    public init(completedRests: Int) {
        self.completedRests = min(1_000_000, max(0, completedRests))
    }

    public init(profile: ForestProfile) {
        self.init(completedRests: profile.completedRests)
    }

    public var unlockedMilestones: [ForestEcologyMilestone] {
        ForestEcologyMilestone.allCases.filter(isUnlocked)
    }

    public var nextMilestone: ForestEcologyMilestone? {
        ForestEcologyMilestone.allCases.first { !isUnlocked($0) }
    }

    public var restsUntilNext: Int? {
        nextMilestone.map { $0.unlockAfter - completedRests }
    }

    public var progressTowardsNext: Double {
        guard let nextMilestone else { return 1 }
        let previous = unlockedMilestones.last?.unlockAfter ?? 24
        let span = nextMilestone.unlockAfter - previous
        return min(1, max(0, Double(completedRests - previous) / Double(span)))
    }

    public func isUnlocked(_ milestone: ForestEcologyMilestone) -> Bool {
        completedRests >= milestone.unlockAfter
    }

    public func milestones(inGrove index: Int) -> [ForestEcologyMilestone] {
        let currentGrove = ForestLandscape(completedRests: completedRests).currentGroveIndex
        guard index >= 0, index <= currentGrove else { return [] }
        return unlockedMilestones.filter { $0.groveIndex == index }
    }

    public var nextMilestoneText: String {
        guard let next = nextMilestone, let remaining = restsUntilNext else {
            return "池塘、石桥与林间访客都已留下。每三次休息，继续种下一棵树。"
        }
        return "再完成 \(remaining) 次休息，第 \(next.groveIndex + 1) 片林地将出现\(next.title)。"
    }

    public static func milestone(at completedRests: Int) -> ForestEcologyMilestone? {
        ForestEcologyMilestone.allCases.first { $0.unlockAfter == completedRests }
    }
}
