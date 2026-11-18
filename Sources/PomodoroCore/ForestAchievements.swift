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
    case fourWeeks, twelveWeeks, twentySixWeeks, mixedGrove

    public var id: String { rawValue }

    public var category: ForestAchievementCategory {
        switch self {
        case .firstRest, .firstTree, .flowerPath, .stream: return .beginnings
        case .mushrooms, .fullGrove, .newGrove, .thirdGrove, .hundredRests,
             .fourWeeks, .twelveWeeks, .twentySixWeeks: return .exploration
        case .twoSpecies, .fourSpecies, .sixSpecies, .mixedGrove: return .diversity
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
        case .fourWeeks: return "四页森林手札"
        case .twelveWeeks: return "一季的绿意"
        case .twentySixWeeks: return "半年的林间故事"
        case .mixedGrove: return "同一片林间相遇"
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
        case .fourWeeks: return "四个有过停顿的周，留成了四处不同的风景。中间的空白，也是生活的一部分。"
        case .twelveWeeks: return "翻过十二页森林，零散的休息已经写下一季的绿意。"
        case .twentySixWeeks: return "二十六个有过休息的周，慢慢积成一本厚厚的森林年鉴。"
        case .mixedGrove: return "三种树在同一周的林地长成，相互陪伴，也各有自己的模样。"
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
        case .fourWeeks: return "在 4 个不同的周完成休息，无需连续。"
        case .twelveWeeks: return "在 12 个不同的周完成休息，无需连续。"
        case .twentySixWeeks: return "在 26 个不同的周完成休息，无需连续。"
        case .mixedGrove: return "在同一周的林地实际长成 3 种不同的树。"
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
        case .fourWeeks, .twelveWeeks, .twentySixWeeks: return "book.closed"
        case .mixedGrove: return "tree.fill"
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
        case .fourWeeks: return 4
        case .twelveWeeks: return 12
        case .twentySixWeeks: return 26
        case .mixedGrove: return 3
        }
    }
}

public struct ForestAchievementProgress: Identifiable, Equatable, Sendable {
    public let achievement: ForestAchievement
    public let current: Double
    public let target: Double
    public let story: String
    public let requirement: String
    /// A previously earned legacy footprint remains earned after the rule changes.
    public let isLegacyRecognition: Bool
    fileprivate let unit: ProgressUnit
    public var id: String { achievement.id }
    public var isUnlocked: Bool { isLegacyRecognition || current >= target }
    public var fraction: Double { isLegacyRecognition ? 1 : min(1, max(0, current / target)) }

    fileprivate enum ProgressUnit: Equatable, Sendable { case rests, trees, weeks, species, sameWeekSpecies, seconds }

    public var progressText: String {
        if isLegacyRecognition { return "旧版足迹 · 已保留" }
        let shown = min(current, target)
        switch unit {
        case .species: return "\(Int(shown)) / \(Int(target)) 种成熟树"
        case .sameWeekSpecies: return "\(Int(shown)) / \(Int(target)) 种同周成树"
        case .weeks: return "\(Int(shown)) / \(Int(target)) 个有休息的周"
        case .trees: return "\(Int(shown)) / \(Int(target)) 棵成树"
        case .seconds: return "\(Self.duration(shown)) / \(Self.duration(target))"
        case .rests: return "\(Int(shown)) / \(Int(target)) 次休息"
        }
    }

    private static func duration(_ seconds: Double) -> String {
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

/// Derived from the current forest's actual data. Weekly milestones count only
/// weeks with completed rests; opening a new empty week cannot earn anything.
public struct ForestAchievements: Equatable, Sendable {
    public let items: [ForestAchievementProgress]

    public init(profile: ForestProfile) {
        let matureSpecies = Set(profile.trees.map(\.species)).count
        let journey = profile.weeklyJourney
        let weeks = journey?.weeks ?? []
        let weekly = journey != nil
        let legacyRests = journey?.legacyCompletedRests ?? profile.completedRests
        let maxWeekRests = weeks.map(\.completedRests).max() ?? 0
        let maxWeekTrees = weeks.map { $0.treeIDs.count }.max() ?? 0
        let speciesByTreeID = Dictionary(uniqueKeysWithValues: profile.trees.map { ($0.id, $0.species) })
        let maxWeekSpecies = weeks.map { week in
            Set(week.treeIDs.compactMap { speciesByTreeID[$0] }).count
        }.max() ?? 0
        let ecology = ForestEcology(profile: profile)
        items = ForestAchievement.allCases.map { achievement in
            var current = Double(profile.completedRests)
            var target = achievement.target
            var unit = ForestAchievementProgress.ProgressUnit.rests
            var story = achievement.story
            var requirement = achievement.requirement
            var legacyEarned = false
            switch achievement {
            case .twoSpecies, .fourSpecies, .sixSpecies:
                current = Double(matureSpecies)
                unit = .species
            case .tenMinutes, .oneHour, .threeHours:
                current = profile.totalRestSeconds
                unit = .seconds
            case .fourWeeks, .twelveWeeks, .twentySixWeeks:
                current = Double(weeks.count)
                unit = .weeks
            case .mixedGrove:
                current = Double(maxWeekSpecies)
                unit = .sameWeekSpecies
            default: break
            }
            if weekly {
                switch achievement {
                case .firstTree:
                    current = Double(profile.trees.count); target = 1; unit = .trees
                    requirement = "在这份森林实际长成第一棵树。"
                case .flowerPath, .stream, .mushrooms:
                    current = Double(maxWeekRests)
                    legacyEarned = legacyRests >= Int(achievement.target)
                    requirement = "在同一周的林地累计完成 \(Int(target)) 次休息。"
                case .fullGrove:
                    current = Double(maxWeekTrees); target = 4; unit = .trees
                    legacyEarned = legacyRests >= 48
                    requirement = "在同一周的林地实际长成 4 棵树。"
                    story = "一周的小停顿，长成了一片小树林。"
                case .newGrove, .thirdGrove:
                    current = Double(weeks.count); target = achievement == .newGrove ? 2 : 3; unit = .weeks
                    legacyEarned = legacyRests >= Int(achievement.target)
                    requirement = "在 \(Int(target)) 个不同的周完成休息，无需连续。"
                    story = "这一周，也有属于自己的森林。过去的风景留在年鉴，随时可以回去看看。"
                case .pond, .bridge, .visitors:
                    let milestone: ForestEcologyMilestone = achievement == .pond ? .pond : achievement == .bridge ? .bridge : .visitors
                    current = Double(weeks.count); target = Double(milestone.weeklyUnlockAfter); unit = .weeks
                    if case .legacyGrove? = ecology.location(for: milestone) { legacyEarned = true }
                    requirement = ecology.requirementText(for: milestone)
                    story = ecology.detail(for: milestone)
                default: break
                }
            }
            let retained = legacyEarned && (current < target || achievement.category == .ecology)
            if retained {
                story = "这枚足迹随最初的森林保留。" + achievement.story
                requirement = "旧版累计完成 \(Int(achievement.target)) 次休息时已获得，升级后保留。"
            }
            return ForestAchievementProgress(achievement: achievement, current: current, target: target,
                story: story, requirement: requirement, isLegacyRecognition: retained, unit: unit)
        }
    }

    public var unlockedCount: Int { items.filter(\.isUnlocked).count }
    public var totalCount: Int { items.count }

    public var nextAchievement: ForestAchievementProgress? {
        items.filter { !$0.isUnlocked }.reduce(nil) { nearest, item in
            guard let nearest else { return item }
            return item.fraction > nearest.fraction ? item : nearest
        }
    }

    public func progress(for achievement: ForestAchievement) -> ForestAchievementProgress {
        items.first { $0.achievement == achievement }!
    }

    public func items(in category: ForestAchievementCategory) -> [ForestAchievementProgress] {
        items.filter { $0.achievement.category == category }
    }
}
