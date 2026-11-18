import Foundation

/// Small, lasting details in a dated forest; never extra growth or currency.
public enum ForestEncounterKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case robin, bluebird, goldenMushrooms

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .robin: return "小红雀来歇脚"
        case .bluebird: return "小蓝鸟来做客"
        case .goldenMushrooms: return "草边的金色蘑菇"
        }
    }

    public var detail: String {
        switch self {
        case .robin: return "一只小红雀停在林间，陪这片森林歇一会儿。"
        case .bluebird: return "一只小蓝鸟在草边探了探头，留下轻巧的身影。"
        case .goldenMushrooms: return "草丛里长出一簇金色小蘑菇，像藏着一点阳光。"
        }
    }
}

/// One completed day's saved chance, including a nil result. Its ID is the
/// actual completed rest ID, so relaunching or viewing cannot draw again.
public struct ForestEncounterRoll: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let kind: ForestEncounterKind?

    public init(id: UUID, occurredAt: Date, kind: ForestEncounterKind?) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
    }
}

/// Version-one encounter policy. Keep these stable so saved outcomes can be
/// validated after a restart without using Swift's process-randomized Hasher.
enum ForestEncounterPolicy {
    static func kind(seed: UInt64, weekID: String, restID: UUID,
                     previous: [ForestEncounterRoll]) -> ForestEncounterKind? {
        let seen = Set(previous.compactMap(\.kind))
        guard seen.count < 2 else { return nil }
        let guaranteed = previous.count >= 2 && seen.isEmpty
        guard guaranteed || hash(seed: seed, weekID: weekID, restID: restID, salt: "chance") % 4 == 0 else {
            return nil
        }
        let available = ForestEncounterKind.allCases.filter { !seen.contains($0) }
        let value = hash(seed: seed, weekID: weekID, restID: restID, salt: "kind")
        return available[Int(value % UInt64(available.count))]
    }

    private static func hash(seed: UInt64, weekID: String, restID: UUID, salt: String) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in "encounter-v1|\(seed)|\(weekID)|\(restID.uuidString.lowercased())|\(salt)".utf8 {
            value = (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

extension ForestWeek {
    /// Successful encounters remain in their original week, including in the
    /// yearbook. Old archives have no rolls and are never backfilled on read.
    public var encounters: [ForestEncounterRoll] { (encounterRolls ?? []).filter { $0.kind != nil } }

    var encounterCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func validateEncounters(seed: UInt64? = nil) throws {
        let rolls = encounterRolls ?? []
        let kinds = rolls.compactMap(\.kind)
        let days = rolls.map { encounterCalendar.startOfDay(for: $0.occurredAt) }
        guard rolls.count <= 7,
              Set(rolls.map(\.id)).count == rolls.count,
              Set(rolls.map(\.id)).isSubset(of: Set(restIDs)),
              Set(days).count == rolls.count,
              kinds.count <= 2, Set(kinds).count == kinds.count,
              rolls.allSatisfy({ $0.occurredAt >= startDate && $0.occurredAt < endDate }) else {
            throw ForestDataError.invalid("林间偶遇的日期或休息记录不完整。")
        }
        var lastIndex = -1
        var previous: [ForestEncounterRoll] = []
        for roll in rolls {
            try ForestDataValidation.validateDate(roll.occurredAt, field: "林间偶遇日期")
            guard let index = restIDs.firstIndex(of: roll.id), index > lastIndex else {
                throw ForestDataError.invalid("林间偶遇的休息顺序无效。")
            }
            lastIndex = index
            if let seed {
                guard roll.kind == ForestEncounterPolicy.kind(seed: seed, weekID: id,
                                                              restID: roll.id, previous: previous) else {
                    throw ForestDataError.invalid("林间偶遇与保存的抽取结果不一致。")
                }
            }
            previous.append(roll)
        }
    }
}
