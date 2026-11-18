import Foundation

public enum ForestAchievementCategory: String, CaseIterable, Identifiable, Sendable {
    case beginnings, exploration, diversity, ecology, restTime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .beginnings: return "初见绿意"
        case .exploration: return "漫步林地"
        case .diversity: return "树木朋友"
        case .ecology: return "林间发现"
        case .restTime: return "留给自己的时间"
        }
    }

    public var subtitle: String {
        switch self {
        case .beginnings: return "从一抹嫩绿，到有花有溪的小小森林。"
        case .exploration: return "走过熟悉的林地，也为新的树留下一点空间。"
        case .diversity: return "让不同的树，在同一片森林里相遇。"
        case .ecology: return "慢慢休息，风景也会慢慢来到林间。"
        case .restTime: return "零散的停顿，也值得好好留下。"
        }
    }
}

/// A catalogue of earned forest facts. These are derived views of one local
/// profile, never additional rewards, tasks, timers or persisted claim flags.
public enum ForestAchievement: String, CaseIterable, Identifiable, Sendable {
    case firstRest, firstTree, flowerPath, stream
    case mushrooms, fullGrove, newGrove, thirdGrove, hundredRests
    case twoSpecies, fourSpecies, sixSpecies
    case pond, bridge, visitors
    case tenMinutes, oneHour, threeHours

    public var id: String { rawValue }

    public var category: ForestAchievementCategory {
        switch self {
        case .firstRest, .firstTree, .flowerPath, .stream: return .beginnings
        case .mushrooms, .fullGrove, .newGrove, .thirdGrove, .hundredRests: return .exploration
        case .twoSpecies, .fourSpecies, .sixSpecies: return .diversity
        case .pond, .bridge, .visitors: return .ecology
        case .tenMinutes, .oneHour, .threeHours: return .restTime
        }
    }

    public var title: String {
        switch self {
        case .firstRest: return "第一抹绿"
        case .firstTree: return "有树在等你"
        case .flowerPath: return "花开的小路"
        case .stream: return "听见溪流"
        case .mushrooms: return "草丛里的小伞"
        case .fullGrove: return "一片林地的回忆"
        case .newGrove: return "去下一片绿地"
        case .thirdGrove: return "森林的另一边"
        case .hundredRests: return "一百次小停顿"
        case .twoSpecies: return "树有了新朋友"
        case .fourSpecies: return "各有各的绿"
        case .sixSpecies: return "六种树的合影"
        case .pond: return "水边来坐坐"
        case .bridge: return "走过小石桥"
        case .visitors: return "兔子来串门"
        case .tenMinutes: return "攒下一杯茶的时间"
        case .oneHour: return "留一小时给自己"
        case .threeHours: return "慢慢积成的时光"
        }
    }

    public var story: String {
        switch self {
        case .firstRest: return "一次短短的停顿，让空地冒出了第一颗嫩芽。"
        case .firstTree: return "小树留下来了。下次回来，它也会在这里。"
        case .flowerPath: return "树下开了小花，熟悉的空地多了一点颜色。"
        case .stream: return "一条溪流来到林间，给小小森林添了几分清凉。"
        case .mushrooms: return "草丛里撑起了小伞，休息后再回来慢慢看。"
        case .fullGrove: return "十六棵树留在第一片林地，每一棵都来自你的停顿。"
        case .newGrove: return "走过第一片森林，下一片空地也开始有了绿意。"
        case .thirdGrove: return "沿着已经长大的森林走走，第三片林地在前面等你。"
        case .hundredRests: return "一百次停下来，积成了属于这片森林的日常。"
        case .twoSpecies: return "第一位新朋友长大了，两种树一起站在林间。"
        case .fourSpecies: return "深绿、浅绿，还有不同的枝叶，森林越来越有自己的样子。"
        case .sixSpecies: return "六种树都在这里长成过，各自留下一份不同的颜色。"
        case .pond: return "第一片林地留下一汪小池塘，水边的绿意一直都在。"
        case .bridge: return "第二片林地搭起了石桥，隔着溪流的风景也连在一起。"
        case .visitors: return "第三片林地迎来小兔子，草丛里有了轻巧的身影。"
        case .tenMinutes: return "那些短短的休息，加起来已经有十分钟了。"
        case .oneHour: return "一点一点，你为自己留出了一小时的休息时光。"
        case .threeHours: return "不必一次留出很多时间，小小停顿也能慢慢积成三小时。"
        }
    }

    public var requirement: String {
        switch self {
        case .twoSpecies: return "在这片森林实际种出 2 种成熟树。"
        case .fourSpecies: return "在这片森林实际种出 4 种成熟树。"
        case .sixSpecies: return "在这片森林实际种出全部 6 种成熟树。"
        case .tenMinutes: return "在这片森林累计完成 10 分钟休息计时。"
        case .oneHour: return "在这片森林累计完成 1 小时休息计时。"
        case .threeHours: return "在这片森林累计完成 3 小时休息计时。"
        default: return "在这片森林累计完成 \(Int(target)) 次休息。"
        }
    }

    public var symbol: String {
        switch self {
        case .firstRest: return "leaf"
        case .firstTree: return "tree"
        case .flowerPath: return "camera.macro"
        case .stream: return "water.waves"
        case .mushrooms: return "umbrella"
        case .fullGrove: return "tree.fill"
        case .newGrove: return "map"
        case .thirdGrove: return "mountain.2"
        case .hundredRests: return "sparkles"
        case .twoSpecies, .fourSpecies, .sixSpecies: return "leaf.circle"
        case .pond: return "drop"
        case .bridge: return "point.topleft.down.to.point.bottomright.curvepath"
        case .visitors: return "hare"
        case .tenMinutes: return "cup.and.saucer"
        case .oneHour: return "sun.max"
        case .threeHours: return "moon.stars"
        }
    }

    fileprivate var target: Double {
        switch self {
        case .firstRest: return 1
        case .firstTree: return 3
        case .flowerPath: return 6
        case .stream: return 12
        case .mushrooms: return 24
        case .fullGrove: return Double(ForestLandscape.restsPerGrove)
        case .newGrove: return Double(ForestLandscape.restsPerGrove + 1)
        case .thirdGrove: return Double(ForestLandscape.restsPerGrove * 2 + 1)
        case .hundredRests: return 100
        case .twoSpecies: return 2
        case .fourSpecies: return 4
        case .sixSpecies: return Double(ForestSpecies.allCases.count)
        case .pond: return Double(ForestEcologyMilestone.pond.unlockAfter)
        case .bridge: return Double(ForestEcologyMilestone.bridge.unlockAfter)
        case .visitors: return Double(ForestEcologyMilestone.visitors.unlockAfter)
        case .tenMinutes: return 600
        case .oneHour: return 3_600
        case .threeHours: return 10_800
        }
    }
}

public struct ForestAchievementProgress: Identifiable, Equatable, Sendable {
    public let achievement: ForestAchievement
    /// The actual profile total, not a rounded or inferred count.
    public let current: Double
    public var target: Double { achievement.target }
    public var id: String { achievement.id }
    public var isUnlocked: Bool { current >= target }
    public var fraction: Double { min(1, max(0, current / target)) }

    public var progressText: String {
        let shown = min(current, target)
        switch achievement.category {
        case .diversity: return "\(Int(shown)) / \(Int(target)) 种成熟树"
        case .restTime: return "\(Self.duration(shown)) / \(Self.duration(target))"
        default: return "\(Int(shown)) / \(Int(target)) 次休息"
        }
    }

    private static func duration(_ seconds: Double) -> String {
        // Never round an incomplete minute up to an unlocked milestone.
        let whole = Int(seconds.rounded(.down))
        let hours = whole / 3_600
        let minutes = whole % 3_600 / 60
        let remainder = whole % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分") }
        if remainder > 0 || parts.isEmpty { parts.append("\(remainder) 秒") }
        return parts.joined(separator: " ")
    }
}

/// Reading this value cannot change a forest or create detailed historical
/// events. Legacy cumulative totals are valid evidence, without invented dates.
public struct ForestAchievements: Equatable, Sendable {
    public let items: [ForestAchievementProgress]

    public init(profile: ForestProfile) {
        let matureSpecies = Set(profile.trees.map(\.species)).count
        items = ForestAchievement.allCases.map { achievement in
            let current: Double
            switch achievement.category {
            case .diversity: current = Double(matureSpecies)
            case .restTime: current = profile.totalRestSeconds
            default: current = Double(profile.completedRests)
            }
            return ForestAchievementProgress(achievement: achievement, current: current)
        }
    }

    public var unlockedCount: Int { items.filter(\.isUnlocked).count }
    public var totalCount: Int { items.count }

    /// The nearest proportional milestone. Ties retain catalogue order so
    /// refreshes do not shuffle suggestions or depend on the wall clock.
    public var nextAchievement: ForestAchievementProgress? {
        items.filter { !$0.isUnlocked }.reduce(nil) { nearest, item in
            guard let nearest else { return item }
            return item.fraction > nearest.fraction ? item : nearest
        }
    }

    public func progress(for achievement: ForestAchievement) -> ForestAchievementProgress {
        // Every allCases entry is constructed exactly once in the initializer.
        items.first { $0.achievement == achievement }!
    }

    public func items(in category: ForestAchievementCategory) -> [ForestAchievementProgress] {
        items.filter { $0.achievement.category == category }
    }
}
