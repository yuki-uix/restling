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
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestRestReward: RestReward?

    private let defaults: UserDefaults
    private let storageKey: String
    private var unreadableOriginal: Data?

    private struct Archive: Codable {
        let version: Int
        let profiles: [ForestProfile]
        let activeProfileID: UUID
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "forestProfiles.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey) {
            if let saved = try? JSONDecoder().decode(Archive.self, from: data),
               saved.version == 1, !saved.profiles.isEmpty,
               Set(saved.profiles.map(\.id)).count == saved.profiles.count,
               saved.profiles.contains(where: { $0.id == saved.activeProfileID }) {
                profiles = saved.profiles
                activeProfileID = saved.activeProfileID
                return
            }
            // Keep the original bytes for recovery; do not silently overwrite them.
            unreadableOriginal = data
            errorMessage = "本机存档未能读取，原始数据已保留。当前使用新的森林档案。"
        }
        let profile = ForestProfile(name: "我的森林")
        profiles = [profile]
        activeProfileID = profile.id
        if unreadableOriginal == nil { save() }
    }

    var current: ForestProfile {
        // Every mutation keeps a nonempty profile collection and a valid selection.
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    func createProfile(name: String) {
        let profile = ForestProfile(name: name)
        profiles.append(profile)
        activeProfileID = profile.id
        save()
    }

    func renameCurrent(_ name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        profiles[index].name = ForestProfile.cleanName(name)
        save()
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        save()
    }

    func selectSpecies(_ species: ForestSpecies) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }),
              profiles[index].isUnlocked(species) else { return }
        profiles[index].selectedSpecies = species
        save()
    }

    @discardableResult
    func completeRest(profileID: UUID, id: UUID, seconds: TimeInterval, date: Date = Date()) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }),
              profiles[index].recordRest(id: id, seconds: seconds, date: date) else { return false }
        save()
        latestRestReward = RestReward(id: id, profileID: profileID, completedRests: profiles[index].completedRests)
        return true
    }

    private func save() {
        do {
            let archive = Archive(version: 1, profiles: profiles, activeProfileID: activeProfileID)
            let encoded = try JSONEncoder().encode(archive)
            if let unreadableOriginal {
                defaults.set(unreadableOriginal, forKey: storageKey + ".unreadableBackup")
                self.unreadableOriginal = nil
            }
            defaults.set(encoded, forKey: storageKey)
        } catch {
            errorMessage = "森林进度暂时无法保存，请保留应用并重试。"
        }
    }
}
