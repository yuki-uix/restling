import Foundation

public enum ForestSpecies: String, Codable, CaseIterable, Identifiable, Sendable {
    case oak, pine, blossom, birch, willow, ginkgo

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .oak: return "橡树"
        case .pine: return "松树"
        case .blossom: return "樱花"
        case .birch: return "白桦"
        case .willow: return "垂柳"
        case .ginkgo: return "银杏"
        }
    }
    public var unlockAfter: Int {
        switch self {
        case .oak: return 0
        case .pine: return 3
        case .blossom: return 6
        case .birch: return 12
        case .willow: return 36
        case .ginkgo: return 72
        }
    }

    public var catalogueDescription: String {
        switch self {
        case .oak: return "圆圆的树冠，浅绿里藏着一点阳光。它是这片森林最初的陪伴。"
        case .pine: return "层层针叶，长成一座小小的绿色尖塔。让林间多一点清凉的深绿。"
        case .blossom: return "柔粉的花冠，像一团轻轻落在枝头的云。给自己的森林留一点春天。"
        case .birch: return "细白的树干带着深色斑纹，轻巧的树冠在枝头舒展。像一束留在林间的柔光。"
        case .willow: return "长长的枝叶轻轻垂下，树冠像一把柔软的绿伞。让林地多一份慢慢晃动的安静。"
        case .ginkgo: return "向上展开的扇形树冠，藏着温暖的金黄。让已经长大的森林，留下一片秋日的光。"
        }
    }

    public var unlockStory: String {
        unlockAfter == 0 ? "从第一片空地开始，就可以培育橡树。" :
            "累计完成 \(unlockAfter) 次休息后，可以选择培育\(title)。"
    }
}

public struct ForestTree: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let species: ForestSpecies
    public let plantedAt: Date

    public init(id: UUID = UUID(), species: ForestSpecies, plantedAt: Date = Date()) {
        self.id = id
        self.species = species
        self.plantedAt = plantedAt
    }
}

/// An individual, local forest. Only completed rests are allowed into the ledger.
public struct ForestProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var selectedSpecies: ForestSpecies
    public private(set) var completedRests: Int
    public private(set) var totalRestSeconds: TimeInterval
    public private(set) var trees: [ForestTree]
    public let seed: UInt64
    private var creditedRestIDs: Set<UUID>
    public private(set) var weeklyJourney: ForestWeeklyJourney?

    public init(name: String) {
        id = UUID()
        self.name = Self.cleanName(name)
        selectedSpecies = .oak
        completedRests = 0
        totalRestSeconds = 0
        trees = []
        seed = UInt64.random(in: 0...UInt64.max)
        creditedRestIDs = []
        weeklyJourney = nil
    }

    public var growthCount: Int { weeklyJourney?.growthCount ?? completedRests % 3 }
    public var growthTarget: Int { weeklyJourney?.growthTarget ?? 3 }
    public var growthStage: Int {
        guard growthCount > 0 else { return 0 }
        return growthProgress < 0.5 ? 1 : 2
    }
    public var growthProgress: Double { Double(growthCount) / Double(growthTarget) }
    public var restsUntilTree: Int { growthTarget - growthCount }
    public var legacyTreeCount: Int { weeklyJourney?.legacyTreeCount ?? trees.count }
    public var legacyTrees: [ForestTree] { Array(trees.prefix(legacyTreeCount)) }

    /// Production stores activate weekly growth explicitly, so decoding an old
    /// backup never fabricates dates or silently changes its contents.
    @discardableResult
    public mutating func enableWeeklyGrowth(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard weeklyJourney == nil,
              let journey = ForestWeeklyJourney(profile: self, date: date, calendar: calendar) else { return false }
        weeklyJourney = journey
        return true
    }

    public func trees(inWeekID weekID: String) -> [ForestTree] {
        guard let journey = weeklyJourney else { return [] }
        var start = journey.legacyTreeCount
        for week in journey.weeks {
            let end = start + week.treeIDs.count
            if week.id == weekID { return Array(trees[start..<end]) }
            start = end
        }
        return []
    }

    @discardableResult
    public mutating func moveTree(id treeID: UUID, to slot: Int, inWeekID weekID: String,
                                  at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard var journey = weeklyJourney,
              journey.move(treeID: treeID, to: slot, weekID: weekID, date: date, calendar: calendar) else { return false }
        weeklyJourney = journey
        return true
    }

    public func isUnlocked(_ species: ForestSpecies) -> Bool {
        completedRests >= species.unlockAfter
    }

    public func containsCreditedRestID(_ id: UUID) -> Bool {
        creditedRestIDs.contains(id)
    }

    /// The caller supplies one stable ID per rest, including retries after saving.
    @discardableResult
    public mutating func recordRest(id restID: UUID, seconds: TimeInterval, date: Date = Date(),
                                    calendar: Calendar = .current) -> Bool {
        guard seconds.isFinite, seconds > 0, seconds <= 86_400,
              date.timeIntervalSinceReferenceDate.isFinite,
              !creditedRestIDs.contains(restID),
              completedRests < 1_000_000 else { return false }
        if var journey = weeklyJourney {
            guard (try? ForestDataValidation.validateDate(date, field: "休息日期")) != nil else { return false }
            let growsTree = journey.growthCount + 1 == journey.growthTarget
            let grownSpecies = completedRests + 1 >= selectedSpecies.unlockAfter ? selectedSpecies : .oak
            journey.append(restID: restID, seconds: seconds, treeID: growsTree ? restID : nil,
                           species: grownSpecies, date: date, calendar: calendar)
            creditedRestIDs.insert(restID)
            completedRests += 1
            totalRestSeconds += seconds
            if growsTree {
                let species = isUnlocked(selectedSpecies) ? selectedSpecies : .oak
                trees.append(ForestTree(id: restID, species: species, plantedAt: date))
            }
            weeklyJourney = journey
            return true
        }
        creditedRestIDs.insert(restID)
        completedRests += 1
        totalRestSeconds += seconds
        if growthStage == 0 {
            // A corrupted or externally altered selection cannot grant a locked tree.
            let species = isUnlocked(selectedSpecies) ? selectedSpecies : .oak
            trees.append(ForestTree(id: restID, species: species, plantedAt: date))
        }
        return true
    }

    public static func cleanName(_ value: String) -> String {
        let cleaned = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        return cleaned.isEmpty ? "我的森林" : cleaned
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, selectedSpecies, completedRests, totalRestSeconds, trees, seed, creditedRestIDs, weeklyJourney
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = Self.cleanName(try container.decode(String.self, forKey: .name))
        selectedSpecies = try container.decode(ForestSpecies.self, forKey: .selectedSpecies)
        completedRests = try container.decode(Int.self, forKey: .completedRests)
        totalRestSeconds = try container.decode(TimeInterval.self, forKey: .totalRestSeconds)
        trees = try container.decode([ForestTree].self, forKey: .trees)
        seed = try container.decode(UInt64.self, forKey: .seed)
        creditedRestIDs = try container.decode(Set<UUID>.self, forKey: .creditedRestIDs)
        weeklyJourney = try container.decodeIfPresent(ForestWeeklyJourney.self, forKey: .weeklyJourney)
        try validateGrowth()
        if !isUnlocked(selectedSpecies) { selectedSpecies = .oak }
    }

    func validateGrowth() throws {
        guard (0...1_000_000).contains(completedRests),
              completedRests == creditedRestIDs.count,
              totalRestSeconds.isFinite, totalRestSeconds >= 0,
              totalRestSeconds <= Double(completedRests) * 86_400,
              Set(trees.map(\.id)).count == trees.count,
              trees.allSatisfy({ creditedRestIDs.contains($0.id) && $0.plantedAt.timeIntervalSinceReferenceDate.isFinite }) else {
            throw ForestDataError.invalid("森林存档的成长记录不完整。")
        }
        if let journey = weeklyJourney {
            try journey.validate(profile: self, creditedIDs: creditedRestIDs)
        } else if trees.count != completedRests / 3 {
            throw ForestDataError.invalid("旧森林存档的成树记录不完整。")
        }
    }
}
