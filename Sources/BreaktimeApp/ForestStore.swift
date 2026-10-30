import Foundation
import Combine
import PomodoroCore

/// Local profiles are intentionally separate from any future account/cloud service.
@MainActor
final class ForestStore: ObservableObject {
    struct RestReward: Identifiable {
        let id: UUID
        let profileID: UUID
        let completedRests: Int

        var title: String {
            if completedRests == 1 { return "你的森林，发芽了。" }
            if completedRests % ForestLandscape.restsPerGrove == 1 { return "新的林地，发芽了。" }
            if completedRests % ForestLandscape.restsPerGrove == 0 { return "这片林地，长满了。" }
            return completedRests % 3 == 0 ? "一棵树留下来了。" : "小树又长大了一点。"
        }
        var detail: String {
            if completedRests == 1 { return "刚刚的休息，留下了第一抹绿。" }
            if completedRests % ForestLandscape.restsPerGrove == 1 { return "上一片森林依然在这里，新的休息会让这里继续生长。" }
            if completedRests % ForestLandscape.restsPerGrove == 0 { return "下一次休息，会为新的土地添一点绿。" }
            return completedRests % 3 == 0 ? "林地也宽了一点。下次休息，再添一点生机。" : "每一次把视线放远，都在为这里添一点生机。"
        }
    }
    @Published private(set) var profiles: [ForestProfile]
    @Published private(set) var activeProfileID: UUID
    @Published private(set) var events: [ForestRestEvent]
    @Published private(set) var recordingStartedAt: Date
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestRestReward: RestReward?

    private let defaults: UserDefaults
    private let storageKey: String
    private var unreadableOriginal: Data?

    private struct LegacyArchive: Codable {
        let version: Int
        let profiles: [ForestProfile]
        let activeProfileID: UUID
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "forestProfiles.v1",
         now: () -> Date = Date.init) {
        self.defaults = defaults
        self.storageKey = storageKey
        let profile = ForestProfile(name: "我的森林")
        profiles = [profile]
        activeProfileID = profile.id
        events = []
        let startedAt = now()
        recordingStartedAt = startedAt.timeIntervalSinceReferenceDate.isFinite ? startedAt : Date()
        if let data = defaults.data(forKey: storageKey) {
            if let saved = try? JSONDecoder().decode(ForestArchive.self, from: data) {
                apply(saved)
                return
            }
            if let legacy = try? JSONDecoder().decode(LegacyArchive.self, from: data),
               legacy.version == 1,
               let migrated = try? ForestArchive(profiles: legacy.profiles,
                   activeProfileID: legacy.activeProfileID, recordingStartedAt: recordingStartedAt),
               let encoded = try? JSONEncoder().encode(migrated) {
                // Unknown historical dates stay unknown. Preserve the exact v1
                // bytes and cumulative growth; never fabricate past events.
                preserveOriginal(data, primaryKey: storageKey + ".legacyV1Backup")
                defaults.set(encoded, forKey: storageKey)
                apply(migrated)
                return
            }
            // Keep the original bytes for recovery; do not silently overwrite them.
            unreadableOriginal = data
            errorMessage = "本机存档未能读取，原始数据已保留。当前使用新的森林档案。"
            return
        }
        saveCurrent()
    }

    var current: ForestProfile {
        // Every mutation keeps a nonempty profile collection and a valid selection.
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    /// A backup coordinator must preserve unreadable original bytes rather than
    /// advertise the fallback forest as the user's complete existing data.
    var canSafelyReplace: Bool { unreadableOriginal == nil }

    func rawArchiveData() -> Data? {
        unreadableOriginal ?? defaults.data(forKey: storageKey)
    }

    func snapshot() throws -> ForestArchive {
        try ForestArchive(profiles: profiles, activeProfileID: activeProfileID,
                          events: events, recordingStartedAt: recordingStartedAt)
    }

    /// Replace a validated dataset without replaying events or granting rewards.
    /// Encoding completes before the current dataset or its persisted key changes.
    func replace(with archive: ForestArchive) throws {
        try commit(archive)
        latestRestReward = nil
    }

    /// Restore exact unreadable bytes from a local safety copy. A readable
    /// archive must use the validated replacement path instead of this fallback.
    func restoreUnreadableOriginal(_ data: Data) throws {
        guard data.count <= RestlingBackup.maxDataSize else {
            throw ForestDataError.invalid("原始存档超过恢复大小限制。")
        }
        let decoder = JSONDecoder()
        if (try? decoder.decode(ForestArchive.self, from: data)) != nil {
            throw ForestDataError.invalid("这份森林存档可以读取，请使用普通备份恢复入口。")
        }
        if let legacy = try? decoder.decode(LegacyArchive.self, from: data), legacy.version == 1,
           (try? ForestArchive(profiles: legacy.profiles, activeProfileID: legacy.activeProfileID)) != nil {
            throw ForestDataError.invalid("这份旧森林存档可以读取，不能按损坏原件恢复。")
        }
        let profile = ForestProfile(name: "我的森林")
        let fallback = try ForestArchive(profiles: [profile], activeProfileID: profile.id)
        // Check that the temporary presentation state is also encodable before
        // replacing anything. Its bytes are never written over the original.
        _ = try JSONEncoder().encode(fallback)
        defaults.set(data, forKey: storageKey)
        unreadableOriginal = data
        apply(fallback)
        latestRestReward = nil
        errorMessage = "已恢复导入前的原始存档。原件仍未能读取，已完整保留；当前显示临时森林。"
    }

    func createProfile(name: String) {
        let profile = ForestProfile(name: name)
        save(profiles: profiles + [profile], activeProfileID: profile.id)
    }

    func renameCurrent(_ name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var candidate = profiles
        candidate[index].name = ForestProfile.cleanName(name)
        save(profiles: candidate, activeProfileID: activeProfileID)
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        save(profiles: profiles, activeProfileID: id)
    }

    func selectSpecies(_ species: ForestSpecies) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }),
              profiles[index].isUnlocked(species) else { return }
        var candidate = profiles
        candidate[index].selectedSpecies = species
        save(profiles: candidate, activeProfileID: activeProfileID)
    }

    @discardableResult
    func completeRest(profileID: UUID, id: UUID, seconds: TimeInterval, date: Date = Date()) -> Bool {
        guard canSafelyReplace, let index = profiles.firstIndex(where: { $0.id == profileID }),
              !hasRecordedRest(id) else { return false }
        var candidate = profiles
        guard candidate[index].recordRest(id: id, seconds: seconds, date: date) else { return false }
        let event = ForestRestEvent(id: id, profileID: profileID, occurredAt: date,
                                    configuredSeconds: seconds, outcome: .completed)
        do {
            let archive = try ForestArchive(profiles: candidate, activeProfileID: activeProfileID,
                events: events + [event], recordingStartedAt: recordingStartedAt)
            try commit(archive)
            latestRestReward = RestReward(id: id, profileID: profileID,
                                         completedRests: candidate[index].completedRests)
            return true
        } catch {
            reportSaveFailure()
            return false
        }
    }

    /// A terminal skipped timer is recorded, but never counted as forest growth.
    @discardableResult
    func skipRest(profileID: UUID, id: UUID, seconds: TimeInterval, date: Date = Date()) -> Bool {
        guard canSafelyReplace, profiles.contains(where: { $0.id == profileID }),
              !hasRecordedRest(id) else { return false }
        let event = ForestRestEvent(id: id, profileID: profileID, occurredAt: date,
                                    configuredSeconds: seconds, outcome: .skipped)
        do {
            let archive = try ForestArchive(profiles: profiles, activeProfileID: activeProfileID,
                events: events + [event], recordingStartedAt: recordingStartedAt)
            try commit(archive)
            return true
        } catch {
            reportSaveFailure()
            return false
        }
    }

    private func hasRecordedRest(_ id: UUID) -> Bool {
        events.contains(where: { $0.id == id }) || profiles.contains(where: { $0.containsCreditedRestID(id) })
    }

    private func saveCurrent() {
        save(profiles: profiles, activeProfileID: activeProfileID)
    }

    private func save(profiles: [ForestProfile], activeProfileID: UUID) {
        do {
            try commit(ForestArchive(profiles: profiles, activeProfileID: activeProfileID,
                                    events: events, recordingStartedAt: recordingStartedAt))
        } catch {
            reportSaveFailure()
        }
    }

    private func commit(_ archive: ForestArchive) throws {
        try archive.validate()
        let encoded = try JSONEncoder().encode(archive)
        if let unreadableOriginal {
            preserveOriginal(unreadableOriginal, primaryKey: storageKey + ".unreadableBackup")
        }
        // Forests and terminal events are one encoded value, so a retry cannot
        // persist growth without its event (or an event without its growth).
        defaults.set(encoded, forKey: storageKey)
        unreadableOriginal = nil
        apply(archive)
        errorMessage = nil
    }

    private func apply(_ archive: ForestArchive) {
        profiles = archive.profiles
        activeProfileID = archive.activeProfileID
        events = archive.events
        recordingStartedAt = archive.recordingStartedAt
    }

    private func preserveOriginal(_ data: Data, primaryKey: String) {
        if let previous = defaults.data(forKey: primaryKey), previous != data {
            defaults.set(data, forKey: primaryKey + "." + UUID().uuidString)
        } else {
            defaults.set(data, forKey: primaryKey)
        }
    }

    private func reportSaveFailure() {
        errorMessage = "森林进度暂时无法保存，现有数据未更改。请保留应用并重试。"
    }
}
