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
        let didGrowTree: Bool
        let startedNewWeek: Bool
        let growthCount: Int
        let growthTarget: Int
        let newDiscoveries: [ForestEcologyMilestone]

        var title: String {
            if let discovery = newDiscoveries.first { return discovery.title + "，来到森林了。" }
            if didGrowTree { return "一棵树，留在了这一周。" }
            if completedRests == 1 { return "你的森林，发芽了。" }
            if startedNewWeek { return "这一周，也留下了一点绿。" }
            return "给小树，添了一点养分。"
        }
        var detail: String {
            if !newDiscoveries.isEmpty { return "新的生态风景已经留下，休息后可以去林地手记看看。" }
            if didGrowTree { return "它会一直留在本周森林。下一棵树，慢慢培育二十四次休息。" }
            return "本轮滋养 \(growthCount) / \(growthTarget)；未成熟的植物会跨周继续培育。"
        }
    }
    @Published private(set) var profiles: [ForestProfile]
    @Published private(set) var activeProfileID: UUID
    @Published private(set) var events: [ForestRestEvent]
    @Published private(set) var recordingStartedAt: Date
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestRestReward: RestReward?

    @Published private(set) var displayDate: Date
    private let clock: () -> Date
    private let fixedCalendar: Calendar?
    private var activeCalendar: Calendar { fixedCalendar ?? .current }

    private let defaults: UserDefaults
    private let storageKey: String
    private var unreadableOriginal: Data?

    private struct LegacyArchive: Codable {
        let version: Int
        let profiles: [ForestProfile]
        let activeProfileID: UUID
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "forestProfiles.v1",
         now: @escaping () -> Date = Date.init, calendar: Calendar? = nil) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.clock = now
        self.fixedCalendar = calendar
        let candidateDate = now()
        let startedAt = ForestWeek.containing(candidateDate, calendar: calendar ?? .current) != nil ? candidateDate : Date()
        displayDate = startedAt
        var profile = ForestProfile(name: "我的森林")
        profile.enableWeeklyGrowth(at: startedAt, calendar: calendar ?? .current)
        profiles = [profile]
        activeProfileID = profile.id
        events = []
        recordingStartedAt = startedAt
        if let data = defaults.data(forKey: storageKey) {
            if let saved = try? JSONDecoder().decode(ForestArchive.self, from: data) {
                apply(saved)
                if saved.profiles.contains(where: { $0.weeklyJourney == nil }) {
                    preserveOriginal(data, primaryKey: storageKey + ".legacyV2Backup")
                    saveCurrent()
                }
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
                saveCurrent()
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

    var currentWeek: ForestWeek? {
        current.weeklyJourney?.displayWeek(at: displayDate, calendar: activeCalendar)
    }

    /// The existing application ticker refreshes this presentation date. No
    /// empty week is persisted and no progress is awarded by viewing a new week.
    func refreshWeek(at date: Date? = nil) {
        let next = date ?? clock()
        guard ForestWeek.containing(next, calendar: activeCalendar) != nil else { return }
        let previous = current.weeklyJourney?.displayWeek(at: displayDate, calendar: activeCalendar)
        let incoming = current.weeklyJourney?.displayWeek(at: next, calendar: activeCalendar)
        if previous?.id != incoming?.id || previous?.timeZoneIdentifier != incoming?.timeZoneIdentifier {
            displayDate = next
        }
    }

    @discardableResult
    func moveTree(id: UUID, to slot: Int) -> Bool {
        guard canSafelyReplace, let week = currentWeek,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return false }
        var candidate = profiles
        guard candidate[index].moveTree(id: id, to: slot, inWeekID: week.id,
                                        at: clock(), calendar: activeCalendar) else { return false }
        do {
            try commit(ForestArchive(profiles: candidate, activeProfileID: activeProfileID,
                                     events: events, recordingStartedAt: recordingStartedAt))
            return true
        } catch { reportSaveFailure(); return false }
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
        var profile = ForestProfile(name: "我的森林")
        profile.enableWeeklyGrowth(at: clock(), calendar: activeCalendar)
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
        var profile = ForestProfile(name: name)
        profile.enableWeeklyGrowth(at: clock(), calendar: activeCalendar)
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
        let before = candidate[index]
        candidate[index].enableWeeklyGrowth(at: date, calendar: activeCalendar)
        guard candidate[index].recordRest(id: id, seconds: seconds, date: date, calendar: activeCalendar) else { return false }
        let after = candidate[index]
        let event = ForestRestEvent(id: id, profileID: profileID, occurredAt: date,
                                    configuredSeconds: seconds, outcome: .completed)
        do {
            let archive = try ForestArchive(profiles: candidate, activeProfileID: activeProfileID,
                events: events + [event], recordingStartedAt: recordingStartedAt)
            try commit(archive)
            refreshWeek(at: date)
            latestRestReward = RestReward(id: id, profileID: profileID,
                completedRests: after.completedRests,
                didGrowTree: after.trees.count > before.trees.count,
                startedNewWeek: after.weeklyJourney?.weeks.count != before.weeklyJourney?.weeks.count,
                growthCount: after.growthCount, growthTarget: after.growthTarget,
                newDiscoveries: ForestEcology(profile: after).unlockedMilestones.filter {
                    !ForestEcology(profile: before).isUnlocked($0)
                })
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
        let normalized: ForestArchive
        if archive.profiles.contains(where: { $0.weeklyJourney == nil }) {
            let date = clock()
            let migrated = archive.profiles.map { value -> ForestProfile in
                var profile = value
                profile.enableWeeklyGrowth(at: date, calendar: activeCalendar)
                return profile
            }
            normalized = try ForestArchive(profiles: migrated, activeProfileID: archive.activeProfileID,
                events: archive.events, recordingStartedAt: archive.recordingStartedAt)
        } else { normalized = archive }
        let encoded = try JSONEncoder().encode(normalized)
        if let unreadableOriginal {
            preserveOriginal(unreadableOriginal, primaryKey: storageKey + ".unreadableBackup")
        }
        // Forests and terminal events are one encoded value, so a retry cannot
        // persist growth without its event (or an event without its growth).
        defaults.set(encoded, forKey: storageKey)
        unreadableOriginal = nil
        apply(normalized)
        refreshWeek()
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
