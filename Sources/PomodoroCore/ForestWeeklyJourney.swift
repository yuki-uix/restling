import Foundation

public struct ForestTreePlacement: Codable, Equatable, Sendable {
    public let treeID: UUID
    public let slot: Int

    public init(treeID: UUID, slot: Int) {
        self.treeID = treeID
        self.slot = slot
    }
}

/// A recorded Monday–Sunday forest. End is exclusive and dates retain the
/// timezone in which the week was first recorded. Empty weeks are view values,
/// never yearbook entries.
public struct ForestWeek: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let startDate: Date
    public let endDate: Date
    public let timeZoneIdentifier: String
    public private(set) var restIDs: [UUID]
    public private(set) var totalRestSeconds: TimeInterval
    public private(set) var treeIDs: [UUID]
    public private(set) var placements: [ForestTreePlacement]
    public private(set) var lastGrowthCount: Int
    public private(set) var lastGrowthTarget: Int
    public private(set) var lastSpecies: ForestSpecies
    /// Missing in v3 archives. Nil preserves the fact that no historical
    /// encounter chances were recorded before this feature existed.
    public private(set) var encounterRolls: [ForestEncounterRoll]?

    public var completedRests: Int { restIDs.count }
    public var treeCount: Int { treeIDs.count }
    public var isEmpty: Bool { restIDs.isEmpty }
    public var pageCount: Int { max(1, (treeIDs.count + 15) / 16) }
    public var year: Int { Int(id.prefix(4)) ?? 0 }
    public var month: Int { Int(id.dropFirst(5).prefix(2)) ?? 0 }
    public var monthID: String { String(id.prefix(7)) }

    private init(id: String, startDate: Date, endDate: Date, timeZoneIdentifier: String) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        restIDs = []
        totalRestSeconds = 0
        treeIDs = []
        placements = []
        lastGrowthCount = 0
        lastGrowthTarget = 3
        lastSpecies = .oak
        encounterRolls = []
    }

    public static func containing(_ date: Date, calendar source: Calendar = .current) -> ForestWeek? {
        guard (try? ForestDataValidation.validateDate(date, field: "周日期")) != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date),
              (try? ForestDataValidation.validateDate(interval.start, field: "周开始")) != nil,
              (try? ForestDataValidation.validateDate(interval.end, field: "周结束")) != nil else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: interval.start)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        return ForestWeek(id: key, startDate: interval.start, endDate: interval.end,
                          timeZoneIdentifier: calendar.timeZone.identifier)
    }

    public func slot(for treeID: UUID) -> Int {
        placements.first(where: { $0.treeID == treeID })?.slot ?? treeIDs.firstIndex(of: treeID) ?? 0
    }

    mutating func setSnapshot(count: Int, target: Int, species: ForestSpecies) {
        lastGrowthCount = count
        lastGrowthTarget = target
        lastSpecies = species
    }

    mutating func append(restID: UUID, seconds: TimeInterval, treeID: UUID?) {
        restIDs.append(restID)
        totalRestSeconds += seconds
        if let treeID {
            treeIDs.append(treeID)
            let occupied = Set(placements.map(\.slot))
            let slot = (0..<max(16, pageCount * 16)).first(where: { !occupied.contains($0) })!
            placements.append(ForestTreePlacement(treeID: treeID, slot: slot))
        }
    }

    mutating func recordEncounterChance(restID: UUID, date: Date, seed: UInt64) {
        // A clock/timezone rollback can credit a rest to the retained current
        // week. It must not invent an encounter dated outside that week.
        guard date >= startDate, date < endDate else { return }
        let rolls = encounterRolls ?? []
        let day = encounterCalendar.startOfDay(for: date)
        guard rolls.count < 7,
              !rolls.contains(where: { encounterCalendar.startOfDay(for: $0.occurredAt) == day }) else { return }
        let kind = ForestEncounterPolicy.kind(seed: seed, weekID: id, restID: restID, previous: rolls)
        encounterRolls = rolls + [ForestEncounterRoll(id: restID, occurredAt: date, kind: kind)]
    }

    mutating func move(treeID: UUID, to slot: Int) -> Bool {
        guard slot >= 0, slot < pageCount * 16,
              let index = placements.firstIndex(where: { $0.treeID == treeID }) else { return false }
        let oldSlot = placements[index].slot
        guard oldSlot != slot else { return false }
        if let occupied = placements.firstIndex(where: { $0.slot == slot }) {
            placements[occupied] = ForestTreePlacement(treeID: placements[occupied].treeID, slot: oldSlot)
        }
        placements[index] = ForestTreePlacement(treeID: treeID, slot: slot)
        return true
    }

    func validate(allowEmpty: Bool = false) throws {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw ForestDataError.invalid("周森林的时区无效。")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let expected = Self.containing(startDate, calendar: calendar),
              expected.id == id, expected.startDate == startDate, expected.endDate == endDate,
              allowEmpty || !isEmpty,
              Set(restIDs).count == restIDs.count,
              Set(treeIDs).count == treeIDs.count,
              Set(treeIDs).isSubset(of: Set(restIDs)),
              totalRestSeconds.isFinite, totalRestSeconds >= 0,
              totalRestSeconds <= Double(completedRests) * 86_400,
              completedRests == 0 ? totalRestSeconds == 0 : totalRestSeconds > 0,
              [3, 24].contains(lastGrowthTarget), lastGrowthCount >= 0, lastGrowthCount < lastGrowthTarget,
              placements.count == treeIDs.count,
              Set(placements.map(\.treeID)) == Set(treeIDs),
              Set(placements.map(\.slot)).count == placements.count,
              placements.allSatisfy({ $0.slot >= 0 && $0.slot < pageCount * 16 }) else {
            throw ForestDataError.invalid("周森林的日期、记录或树木布局不完整。")
        }
        try validateEncounters()
    }
}

/// Baseline totals are kept intact. New real completions alone create dated
/// weeks; old event dates and tree dates are never used to reconstruct weeks.
public struct ForestWeeklyJourney: Codable, Equatable, Sendable {
    public let version: Int
    public let startedAt: Date
    public let startingWeek: ForestWeek
    public let legacyCompletedRests: Int
    public let legacyRestSeconds: TimeInterval
    public let legacyTreeCount: Int
    public let legacySelectedSpecies: ForestSpecies
    public private(set) var weeks: [ForestWeek]

    init?(profile: ForestProfile, date: Date, calendar: Calendar) {
        guard let week = ForestWeek.containing(date, calendar: calendar) else { return nil }
        version = 1
        startedAt = date
        startingWeek = week
        legacyCompletedRests = profile.completedRests
        legacyRestSeconds = profile.totalRestSeconds
        legacyTreeCount = profile.trees.count
        legacySelectedSpecies = profile.selectedSpecies
        weeks = []
    }

    public var completedRests: Int { weeks.reduce(0) { $0 + $1.completedRests } }
    public var totalRestSeconds: TimeInterval { weeks.reduce(0) { $0 + $1.totalRestSeconds } }
    public var treeCount: Int { weeks.reduce(0) { $0 + $1.treeIDs.count } }
    public var initialGrowthCount: Int { legacyCompletedRests % 3 }
    public var initialGrowthTarget: Int { legacyCompletedRests == 0 || initialGrowthCount > 0 ? 3 : 24 }
    public var growthTarget: Int { completedRests < initialGrowthTarget - initialGrowthCount ? initialGrowthTarget : 24 }
    public var growthCount: Int {
        let firstRemaining = initialGrowthTarget - initialGrowthCount
        return completedRests < firstRemaining ? initialGrowthCount + completedRests : (completedRests - firstRemaining) % 24
    }
    public var hasLegacyForest: Bool { legacyCompletedRests > 0 || legacyTreeCount > 0 }

    /// A clock or timezone rollback never reopens an already archived week.
    /// The latest recorded header is retained when its civil week is current.
    public func displayWeek(at date: Date, calendar: Calendar = .current) -> ForestWeek {
        let candidate = ForestWeek.containing(date, calendar: calendar) ?? weeks.last ?? startingWeek
        let floor = weeks.last ?? startingWeek
        return candidate.id <= floor.id ? floor : candidate
    }

    mutating func append(restID: UUID, seconds: TimeInterval, treeID: UUID?, species: ForestSpecies, seed: UInt64,
                         date: Date, calendar: Calendar) {
        let current = displayWeek(at: date, calendar: calendar)
        if weeks.last?.id != current.id { weeks.append(current) }
        weeks[weeks.count - 1].append(restID: restID, seconds: seconds, treeID: treeID)
        weeks[weeks.count - 1].recordEncounterChance(restID: restID, date: date, seed: seed)
        let count = growthCount
        let target = growthTarget
        weeks[weeks.count - 1].setSnapshot(count: count, target: target, species: species)
    }

    mutating func move(treeID: UUID, to slot: Int, weekID: String, date: Date, calendar: Calendar) -> Bool {
        guard displayWeek(at: date, calendar: calendar).id == weekID,
              weeks.last?.id == weekID else { return false }
        return weeks[weeks.count - 1].move(treeID: treeID, to: slot)
    }

    func validate(profile: ForestProfile, creditedIDs: Set<UUID>) throws {
        try ForestDataValidation.validateDate(startedAt, field: "每周森林开始时间")
        try startingWeek.validate(allowEmpty: true)
        guard version == 1, startingWeek.isEmpty, startingWeek.treeIDs.isEmpty,
              startedAt >= startingWeek.startDate, startedAt < startingWeek.endDate,
              (0...1_000_000).contains(legacyCompletedRests),
              legacyTreeCount == legacyCompletedRests / 3,
              legacySelectedSpecies.unlockAfter <= legacyCompletedRests,
              legacyRestSeconds.isFinite, legacyRestSeconds >= 0,
              legacyRestSeconds <= Double(legacyCompletedRests) * 86_400,
              weeks.count <= 1_000_000 else {
            throw ForestDataError.invalid("每周森林的旧进度基线无效。")
        }
        var restIDs: [UUID] = []
        var newTreeIDs: [UUID] = []
        var previousID: String?
        var expectedTreeIDs: [UUID] = []
        var count = initialGrowthCount
        var target = initialGrowthTarget
        var processedRests = 0
        let treesByID = Dictionary(uniqueKeysWithValues: profile.trees.map { ($0.id, $0) })
        for week in weeks {
            try week.validate()
            try week.validateEncounters(seed: profile.seed)
            guard week.id >= startingWeek.id, previousID == nil || week.id > previousID! else {
                throw ForestDataError.invalid("每周森林顺序或日期重复。")
            }
            previousID = week.id
            restIDs.append(contentsOf: week.restIDs)
            newTreeIDs.append(contentsOf: week.treeIDs)
            var earnedHere: [UUID] = []
            for id in week.restIDs {
                count += 1
                processedRests += 1
                if count == target {
                    guard let tree = treesByID[id],
                          tree.species.unlockAfter <= legacyCompletedRests + processedRests else {
                        throw ForestDataError.invalid("周森林的树种早于实际解锁条件。")
                    }
                    earnedHere.append(id)
                    expectedTreeIDs.append(id)
                    count = 0
                    target = 24
                }
            }
            guard week.treeIDs == earnedHere,
                  week.lastGrowthCount == count, week.lastGrowthTarget == target,
                  legacyCompletedRests + restIDs.count >= week.lastSpecies.unlockAfter else {
                throw ForestDataError.invalid("周森林的成树记录与培育进度不一致。")
            }
        }
        let newIDs = Set(restIDs)
        let legacyIDs = creditedIDs.subtracting(newIDs)
        let tolerance = max(0.000_001, abs(profile.totalRestSeconds) * 1e-12)
        guard newIDs.count == restIDs.count,
              newIDs.isSubset(of: creditedIDs),
              legacyIDs.count == legacyCompletedRests,
              profile.completedRests == legacyCompletedRests + restIDs.count,
              abs(profile.totalRestSeconds - (legacyRestSeconds + totalRestSeconds)) <= tolerance,
              profile.trees.count == legacyTreeCount + newTreeIDs.count,
              Array(profile.trees.dropFirst(legacyTreeCount).map(\.id)) == expectedTreeIDs,
              profile.trees.prefix(legacyTreeCount).allSatisfy({ legacyIDs.contains($0.id) }),
              newTreeIDs == expectedTreeIDs,
              growthCount == count, growthTarget == target else {
            throw ForestDataError.invalid("每周森林与累计成长记录不一致。")
        }
    }
}
