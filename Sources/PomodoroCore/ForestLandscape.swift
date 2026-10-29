import Foundation

/// Visual territory is derived entirely from earned rest history. Rendering a
/// preview, waiting, or changing a profile never unlocks a piece of landscape.
public struct ForestLandscape: Equatable, Sendable {
    public static let restsPerGrove = 48
    public let completedRests: Int

    public init(completedRests: Int) {
        self.completedRests = min(1_000_000, max(0, completedRests))
    }

    public init(profile: ForestProfile) {
        self.init(completedRests: profile.completedRests)
    }

    /// A filled grove remains current until the first rest in the next one.
    /// Existing groves are retained: this is a viewport, never a reset of history.
    public var currentGroveIndex: Int {
        completedRests == 0 ? 0 : (completedRests - 1) / Self.restsPerGrove
    }

    public var groveCount: Int { currentGroveIndex + 1 }

    public func rests(inGrove index: Int) -> Int {
        // Validate before multiplication so even Int.max/Int.min are safe.
        guard index >= 0, index <= currentGroveIndex else { return 0 }
        return min(Self.restsPerGrove, max(0, completedRests - index * Self.restsPerGrove))
    }

    public var expansionLevel: Int {
        switch completedRests {
        case 0: return 0
        case 1...2: return 1
        case 3...5: return 2
        case 6...11: return 3
        case 12...23: return 4
        default: return 5
        }
    }

    public var expansionProgress: Double { min(1, Double(completedRests) / 24) }
    public var landScale: Double { 0.275 + 0.725 * expansionProgress }
    public var hasVegetation: Bool { completedRests > 0 }
    public var hasCurrentPlant: Bool { completedRests % 3 != 0 }
    public var hasFlowers: Bool { completedRests >= 6 }
    public var hasStream: Bool { completedRests >= 12 }
    public var hasMushrooms: Bool { completedRests >= 24 }
    public var earnedTreeCount: Int { completedRests / 3 }
    public var visibleTreeCount: Int { min(16, earnedTreeCount) }

    public var stageTitle: String {
        switch expansionLevel {
        case 0: return "一小块空地"
        case 1: return completedRests == 1 ? "第一点绿意" : "正在长大的幼苗"
        case 2: return "小小林地"
        case 3: return "林间花径"
        case 4: return "溪流林地"
        default: return "我的休息森林"
        }
    }

    public var nextExpansionAt: Int? {
        [1, 3, 6, 12, 24].first(where: { completedRests < $0 })
    }

    public var nextMilestoneText: String {
        guard let next = nextExpansionAt else { return "每三次休息，一棵新树留在林间。" }
        let remaining = next - completedRests
        switch next {
        case 1: return "完成第一次休息，让空地冒出第一抹绿。"
        case 3: return "再完成 \(remaining) 次休息，第一棵树就会留下来。"
        case 6: return "再完成 \(remaining) 次休息，林间将开出小花。"
        case 12: return "再完成 \(remaining) 次休息，溪流会来到林地。"
        default: return "再完成 \(remaining) 次休息，让小小林地成为休息森林。"
        }
    }
}
