import AppKit
import Combine
import PomodoroCore
import UniformTypeIdentifiers

struct BackupSummary: Equatable {
    let profileCount: Int
    let treeCount: Int
    let eventCount: Int
    let completedRestCount: Int

    init(forest: ForestArchive) {
        self.init(profiles: forest.profiles, eventCount: forest.events.count)
    }

    init(profiles: [ForestProfile], eventCount: Int) {
        profileCount = profiles.count
        treeCount = profiles.reduce(0) { $0 + $1.trees.count }
        self.eventCount = eventCount
        completedRestCount = profiles.reduce(0) { $0 + $1.completedRests }
    }
}

struct BackupReview: Identifiable {
    let id = UUID()
    let fileName: String
    let snapshot: RecoverySnapshot
    let isUndo: Bool
    var backup: RestlingBackup? { snapshot.backup }
    var createdAt: Date { snapshot.createdAt }
    var incoming: BackupSummary? { snapshot.backup.map { BackupSummary(forest: $0.forest) } }
    var isRawOriginal: Bool { snapshot.isRawOriginal }

    init(fileName: String, backup: RestlingBackup, isUndo: Bool) {
        self.init(fileName: fileName, snapshot: RecoverySnapshot(backup: backup), isUndo: isUndo)
    }

    init(fileName: String, snapshot: RecoverySnapshot, isUndo: Bool) {
        self.fileName = fileName
        self.snapshot = snapshot
        self.isUndo = isUndo
    }
}

@MainActor
final class DataBackupController: ObservableObject {
    @Published private(set) var review: BackupReview?
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var recoveryAvailable = false

    private let model: AppModel
    private let updater: UpdateChecker?
    private let recovery: any BackupRecoveryStoring
    private var forestObservation: AnyCancellable?

    init(model: AppModel, updater: UpdateChecker? = nil, recovery: (any BackupRecoveryStoring)? = nil) {
        self.model = model
        self.updater = updater
        self.recovery = recovery ?? LocalBackupRecoveryStore()
        recoveryAvailable = self.recovery.latestURL != nil
        forestObservation = model.forest.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var currentSummary: BackupSummary {
        BackupSummary(profiles: model.forest.profiles, eventCount: model.forest.events.count)
    }
    var recordingStartedAt: Date { model.forest.recordingStartedAt }
    var unreadableWarning: String? {
        model.forest.canSafelyReplace ? nil :
            "本机原始存档未能读取，原件已保留。可以导出原始存档，或选择有效备份修复；恢复前会先另存原始数据，之后仍可撤回。"
    }

    func exportBackup() {
        guard !isBusy else { return }
        clearNotices()
        let raw = !model.forest.canSafelyReplace
        let panel = NSSavePanel()
        panel.title = raw ? "导出原始存档" : "导出 Restling 备份"
        panel.nameFieldStringValue = raw ? "Restling-unreadable-original.json" :
            "Restling-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        isBusy = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isBusy = false }
                guard response == .OK, let url = panel.url else { return }
                do {
                    let data: Data
                    if raw {
                        guard let original = self.model.forest.rawArchiveData() else {
                            throw ForestDataError.invalid("没有找到原始存档。")
                        }
                        data = original
                    } else { data = try self.model.makeBackup().encoded() }
                    try data.write(to: url, options: .atomic)
                    self.message = raw ? "原始存档已导出，原件保持不变。" : "备份已导出，包含全部本机森林、设置与事件。"
                } catch { self.errorMessage = "导出失败：\(error.localizedDescription)" }
            }
        }
    }

    func chooseBackup() {
        guard !isBusy else { return }
        clearNotices()
        let panel = NSOpenPanel()
        panel.title = "选择 Restling 备份"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        isBusy = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url = panel.url else { self.isBusy = false; return }
                do {
                    let backup = try await Task.detached(priority: .userInitiated) {
                        try RestlingBackup.decode(BackupFileIO.read(url))
                    }.value
                    self.review = BackupReview(fileName: url.lastPathComponent, backup: backup, isUndo: false)
                } catch { self.errorMessage = "无法恢复：\(error.localizedDescription) 现有数据未更改。" }
                self.isBusy = false
            }
        }
    }

    /// Pure preparation is also used by integration tests. Nothing is saved or
    /// paused until the person explicitly confirms this immutable candidate.
    func prepareImport(data: Data, fileName: String) throws {
        let backup = try RestlingBackup.decode(data)
        clearNotices()
        review = BackupReview(fileName: fileName, backup: backup, isUndo: false)
    }

    func prepareUndo() {
        guard !isBusy else { return }
        clearNotices()
        do {
            let snapshot = try recovery.loadSnapshot()
            review = BackupReview(fileName: recovery.latestURL?.lastPathComponent ?? "导入前安全副本",
                                  snapshot: snapshot, isUndo: true)
        } catch { errorMessage = "无法读取安全副本：\(error.localizedDescription) 现有数据未更改。" }
    }

    func cancelReview() { guard !isBusy else { return }; review = nil }

    func confirmRestore() {
        guard !isBusy, let review else { return }
        clearNotices()
        isBusy = true
        defer { isBusy = false; recoveryAvailable = recovery.latestURL != nil }
        do {
            // Capture at confirmation time, including events completed while
            // the review was open. Every fallible file operation comes first.
            let previous = try model.makeRecoverySnapshot()
            _ = try recovery.saveSnapshot(previous)
            try model.restoreRecoverySnapshot(review.snapshot)
            updater?.automaticChecksEnabled = review.snapshot.settings.automaticUpdateChecksEnabled
            self.review = nil
            if let incoming = review.incoming {
                message = "已恢复 \(incoming.profileCount) 份森林档案。提醒保持暂停，请按需重新开启；恢复前的数据已另存安全副本。"
            } else {
                message = "已回到此前原始存档的状态。原件仍无法解析并已保留，可再次选择有效备份修复；提醒保持暂停。"
            }
        } catch { errorMessage = "恢复失败：\(error.localizedDescription) 现有森林与设置未更改。" }
    }

    func revealRecoveryFile() {
        guard let url = recovery.latestURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func clearNotices() { errorMessage = nil; message = nil }
}
