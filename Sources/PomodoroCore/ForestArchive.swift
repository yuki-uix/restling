import Foundation

/// Forests and their new terminal rest records are saved in one envelope. A
/// migrated forest may have older cumulative growth without dated event rows.
public struct ForestArchive: Codable, Equatable, Sendable {
    public let version: Int
    public let profiles: [ForestProfile]
    public let activeProfileID: UUID
    public let events: [ForestRestEvent]
    public let recordingStartedAt: Date

    public init(profiles: [ForestProfile], activeProfileID: UUID,
                events: [ForestRestEvent] = [], recordingStartedAt: Date = Date()) throws {
        version = 2
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.events = events
        self.recordingStartedAt = recordingStartedAt
        try validate()
    }

    public func validate() throws {
        guard version == 2 else {
            throw ForestDataError.invalid("暂不支持这个森林存档版本，请使用兼容的 Restling 版本。")
        }
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count,
              profiles.contains(where: { $0.id == activeProfileID }) else {
            throw ForestDataError.invalid("森林档案列表或当前森林无效。")
        }
        try ForestDataValidation.validateDate(recordingStartedAt, field: "森林开始记录的时间")
        guard profiles.allSatisfy({ $0.name == ForestProfile.cleanName($0.name) && $0.isUnlocked($0.selectedSpecies) }) else {
            throw ForestDataError.invalid("森林名称或当前培育树种无效。")
        }
        for profile in profiles {
            for tree in profile.trees {
                try ForestDataValidation.validateDate(tree.plantedAt, field: "树木种下的时间")
            }
        }
        guard Set(events.map(\.id)).count == events.count else {
            throw ForestDataError.invalid("备份中存在重复的休息记录。")
        }

        let owners = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        var completedCounts: [UUID: Int] = [:]
        var completedSeconds: [UUID: TimeInterval] = [:]
        for event in events {
            try event.validate()
            guard let profile = owners[event.profileID] else {
                throw ForestDataError.invalid("休息记录所属的森林不存在。")
            }
            switch event.outcome {
            case .completed:
                guard profile.containsCreditedRestID(event.id) else {
                    throw ForestDataError.invalid("已完成的休息记录与森林成长不一致。")
                }
                completedCounts[event.profileID, default: 0] += 1
                completedSeconds[event.profileID, default: 0] += event.configuredSeconds
            case .skipped:
                guard !profiles.contains(where: { $0.containsCreditedRestID(event.id) }) else {
                    throw ForestDataError.invalid("跳过的休息不能同时获得森林成长。")
                }
            }
        }
        for profile in profiles {
            let count = completedCounts[profile.id, default: 0]
            let seconds = completedSeconds[profile.id, default: 0]
            // Floating-point addition order may differ after a round trip. This
            // tolerance is far smaller than any supported rest duration.
            let tolerance = max(0.000_001, abs(profile.totalRestSeconds) * 1e-12)
            guard count <= profile.completedRests,
                  seconds <= profile.totalRestSeconds + tolerance else {
                throw ForestDataError.invalid("休息记录超过了对应森林的累计成长。")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, profiles, activeProfileID, events, recordingStartedAt
    }

    private struct OriginalProfileChoice: Decodable {
        let name: String
        let selectedSpecies: ForestSpecies
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        profiles = try values.decode([ForestProfile].self, forKey: .profiles)
        let originalChoices = try values.decode([OriginalProfileChoice].self, forKey: .profiles)
        guard zip(originalChoices, profiles).allSatisfy({
            $0.0.name == $0.1.name && $0.0.selectedSpecies == $0.1.selectedSpecies
        }) else {
            throw ForestDataError.invalid("森林名称或当前培育树种无效，备份没有导入。")
        }
        activeProfileID = try values.decode(UUID.self, forKey: .activeProfileID)
        events = try values.decode([ForestRestEvent].self, forKey: .events)
        recordingStartedAt = try values.decode(Date.self, forKey: .recordingStartedAt)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(profiles, forKey: .profiles)
        try values.encode(activeProfileID, forKey: .activeProfileID)
        try values.encode(events, forKey: .events)
        try values.encode(recordingStartedAt, forKey: .recordingStartedAt)
    }
}
