import Foundation
import XCTest
import PomodoroCore
import Darwin
@testable import BreaktimeApp

final class BackupFlowTests: XCTestCase {
    @MainActor
    private final class Clock {
        var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    @MainActor
    private final class Fixture {
        let suite = "BackupFlowTests." + UUID().uuidString
        let defaults: UserDefaults
        let directory: URL
        let clock = Clock()
        let calendar: Calendar
        let model: AppModel
        private var restored: [AppModel] = []

        init(rhythm: EyeRestSettings = EyeRestSettings(intervalMinutes: 1, restSeconds: 5)) throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
            defaults.set(try JSONEncoder().encode(rhythm), forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(
                idlePauseEnabled: false, returnGraceSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)),
                         forKey: "reminderPreferences.v1")
            let clock = self.clock
            model = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
        }

        func relaunch() -> AppModel {
            let clock = self.clock
            let next = AppModel(defaults: defaults, now: { clock.date }, calendar: calendar, startsTicker: false)
            restored.append(next)
            return next
        }

        var persistedValues: NSDictionary {
            NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:])
        }

        func cleanup() {
            model.stop()
            restored.forEach { $0.stop() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor
    private final class MemoryRecovery: BackupRecoveryStoring {
        var saved: [RestlingBackup] = []
        var shouldFail = false
        private(set) var saveCalls = 0
        var latestURL: URL? {
            saved.isEmpty ? nil : URL(fileURLWithPath: "/temporary-test/Restling-before-\(saved.count).json")
        }

        func save(_ backup: RestlingBackup) throws -> URL {
            saveCalls += 1
            if shouldFail { throw ForestDataError.invalid("测试：安全副本磁盘不可写。") }
            saved.append(backup)
            return latestURL!
        }

        func loadLatest() throws -> RestlingBackup {
            guard let last = saved.last else { throw ForestDataError.invalid("测试：没有安全副本。") }
            return last
        }
    }

    @MainActor
    private final class SnapshotFailureRecovery: BackupRecoveryStoring {
        var latestURL: URL? { nil }
        private(set) var saveCalls = 0
        func save(_ backup: RestlingBackup) throws -> URL {
            throw ForestDataError.invalid("测试不应调用旧保存接口。")
        }
        func loadLatest() throws -> RestlingBackup {
            throw ForestDataError.invalid("没有测试安全副本。")
        }
        func saveSnapshot(_ snapshot: RecoverySnapshot) throws -> URL {
            saveCalls += 1
            throw ForestDataError.invalid("测试快照保存失败。")
        }
    }

    private struct ModelState: Equatable {
        let forest: ForestArchive
        let rhythm: EyeRestSettings
        let reminders: ReminderPreferences
        let phase: PomodoroPhase
        let remaining: TimeInterval
        let running: Bool
        let wantsRunning: Bool
        let started: Bool
        let rounds: Int
        let preview: TimeInterval?
        let dnd: Date?
        let snooze: Date?
        let grace: Date?
    }

    @MainActor
    private func state(_ model: AppModel) throws -> ModelState {
        ModelState(forest: try model.forest.snapshot(), rhythm: model.eyeRestSettings,
            reminders: model.reminderPreferences, phase: model.engine.phase,
            remaining: model.engine.remaining, running: model.engine.isRunning,
            wantsRunning: model.wantsRunning, started: model.hasStarted,
            rounds: model.engine.completedFocusSessions, preview: model.previewRemaining,
            dnd: model.doNotDisturbUntil, snooze: model.snoozeUntil, grace: model.returnGraceUntil)
    }

    @MainActor
    private func populatedBackup(_ f: Fixture) throws -> RestlingBackup {
        f.model.forest.renameCurrent("备份里的森林")
        let owner = f.model.forest.current.id
        for _ in 0..<3 {
            XCTAssertTrue(f.model.forest.completeRest(profileID: owner, id: UUID(), seconds: 20,
                                                     date: f.clock.date))
        }
        XCTAssertTrue(f.model.forest.skipRest(profileID: owner, id: UUID(), seconds: 20, date: f.clock.date))
        f.model.forest.selectSpecies(.pine)
        f.model.forest.createProfile(name: "第二片林地")
        f.model.applyReminderPreferences(ReminderPreferences(weekdays: [1, 4, 7],
            startMinute: 1_320, endMinute: 360, idlePauseEnabled: false,
            idleThresholdSeconds: 600, returnGraceSeconds: 0, prewarningSeconds: 30,
            startSoundEnabled: false, endSoundEnabled: true))
        f.defaults.set("rainy", forKey: "forestWeatherPreference.v1")
        f.defaults.set(true, forKey: "restForestOnboarding.v1")
        f.defaults.set(false, forKey: "appUpdates.v1.automaticChecksEnabled")
        return try f.model.makeBackup()
    }

    @MainActor
    func testPreparingAndCancellingImportDoNotMutateOrPauseTheCurrentData() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        let incoming = try populatedBackup(source)
        f.model.nextPhase()
        f.model.advanceTimer(by: 1)
        let original = try state(f.model)
        let raw = f.persistedValues
        let recovery = MemoryRecovery()
        let controller = DataBackupController(model: f.model, recovery: recovery)

        try controller.prepareImport(data: incoming.encoded(), fileName: "selected-backup.json")
        XCTAssertEqual(controller.review?.fileName, "selected-backup.json")
        XCTAssertEqual(controller.review?.incoming?.profileCount, 2)
        XCTAssertEqual(controller.review?.incoming?.treeCount, 1)
        XCTAssertEqual(controller.review?.incoming?.eventCount, 4)
        XCTAssertEqual(controller.review?.backup, incoming)
        XCTAssertEqual(try state(f.model), original)
        XCTAssertEqual(f.persistedValues, raw)
        XCTAssertEqual(recovery.saveCalls, 0)
        controller.cancelReview()
        controller.confirmRestore()
        XCTAssertNil(controller.review)
        XCTAssertEqual(try state(f.model), original)
        XCTAssertEqual(f.persistedValues, raw)
        XCTAssertEqual(recovery.saveCalls, 0)
    }

    @MainActor
    func testConfirmedImportRestoresAllPortableDataAndPersistsAPausedFreshTimer() async throws {
        let f = try Fixture(), source = try Fixture(rhythm: EyeRestSettings(intervalMinutes: 7, restSeconds: 17))
        defer { f.cleanup(); source.cleanup() }
        let incoming = try populatedBackup(source)
        f.model.nextPhase()
        let previous = try f.model.makeBackup()
        let recovery = MemoryRecovery()
        let updater = UpdateChecker(configuration: nil, defaults: f.defaults)
        XCTAssertTrue(updater.automaticChecksEnabled)
        let controller = DataBackupController(model: f.model, updater: updater, recovery: recovery)
        try controller.prepareImport(data: incoming.encoded(), fileName: "incoming.json")
        controller.confirmRestore()

        XCTAssertNil(controller.errorMessage)
        XCTAssertNil(controller.review)
        XCTAssertNotNil(controller.message)
        XCTAssertTrue(controller.recoveryAvailable)
        XCTAssertEqual(recovery.saved, [previous])
        XCTAssertEqual(try f.model.makeBackup().forest, incoming.forest)
        XCTAssertEqual(try f.model.makeBackup().settings, incoming.settings)
        XCTAssertEqual(f.model.forest.activeProfileID, incoming.forest.activeProfileID)
        XCTAssertNil(f.model.forest.latestRestReward)
        XCTAssertEqual(f.defaults.string(forKey: "forestWeatherPreference.v1"), "rainy")
        XCTAssertTrue(f.defaults.bool(forKey: "restForestOnboarding.v1"))
        XCTAssertFalse(updater.automaticChecksEnabled)
        XCTAssertFalse(f.model.wantsRunning)
        XCTAssertFalse(f.model.hasStarted)
        XCTAssertFalse(f.model.engine.isRunning)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertEqual(f.model.engine.remaining, 7 * 60)

        let restarted = f.relaunch()
        XCTAssertEqual(try restarted.makeBackup().forest, incoming.forest)
        XCTAssertEqual(try restarted.makeBackup().settings, incoming.settings)
        XCTAssertFalse(restarted.wantsRunning)
        XCTAssertFalse(restarted.engine.isRunning)
        XCTAssertEqual(restarted.engine.phase, .focus)
        XCTAssertEqual(restarted.engine.remaining, 7 * 60)
    }

    @MainActor
    func testRestoringTheSameForestDiscardsTheOldInFlightRestIdentity() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let incoming = try f.model.makeBackup()
        f.model.nextPhase()
        f.model.advanceTimer(by: 2)
        let session = try XCTUnwrap(f.defaults.data(forKey: "reminderSession.v1"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: session) as? [String: Any])
        let oldRest = try XCTUnwrap(raw["rest"] as? [String: Any])
        let oldID = try XCTUnwrap((oldRest["id"] as? String).flatMap(UUID.init(uuidString:)))
        let controller = DataBackupController(model: f.model, recovery: MemoryRecovery())
        try controller.prepareImport(data: incoming.encoded(), fileName: "same-forest.json")
        controller.confirmRestore()
        f.model.advanceTimer(by: 86_400)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        XCTAssertEqual(f.model.engine.phase, .focus)
        f.model.toggleRunning()
        f.model.advanceTimer(by: 1)
        XCTAssertEqual(f.model.engine.phase, .focus)
        XCTAssertTrue(f.model.forest.events.isEmpty)
        f.model.nextPhase()
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.current.completedRests, 1)
        XCTAssertEqual(f.model.forest.events.count, 1)
        XCTAssertNotEqual(f.model.forest.events[0].id, oldID)
        XCTAssertEqual(f.model.forest.events[0].outcome, .completed)
    }

    @MainActor
    func testImportClearsPreviewSnoozeAndDoNotDisturbRatherThanRestoringThoseTransientStates() async throws {
        let source = try Fixture()
        defer { source.cleanup() }
        let incoming = try populatedBackup(source)
        for mode in ["preview", "snooze", "dnd"] {
            let f = try Fixture()
            defer { f.cleanup() }
            switch mode {
            case "preview":
                f.model.preview()
                XCTAssertNotNil(f.model.previewRemaining)
            case "snooze":
                f.model.nextPhase()
                f.model.snooze(minutes: 3)
                XCTAssertNotNil(f.model.snoozeUntil)
            default:
                f.model.pauseFor(minutes: 30)
                XCTAssertNotNil(f.model.doNotDisturbUntil)
            }
            let controller = DataBackupController(model: f.model, recovery: MemoryRecovery())
            try controller.prepareImport(data: incoming.encoded(), fileName: "incoming.json")
            controller.confirmRestore()
            XCTAssertNil(controller.errorMessage)
            XCTAssertNil(f.model.previewRemaining)
            XCTAssertNil(f.model.snoozeUntil)
            XCTAssertNil(f.model.doNotDisturbUntil)
            XCTAssertNil(f.model.returnGraceUntil)
            XCTAssertFalse(f.model.wantsRunning)
            XCTAssertFalse(f.model.engine.isRunning)
            XCTAssertFalse(f.model.showingRest)
            XCTAssertEqual(try f.model.makeBackup().forest, incoming.forest)
        }
    }

    @MainActor
    func testSafetySnapshotCapturesConfirmationTimeAndUndoRestoresItAcrossRelaunch() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        let incoming = try populatedBackup(source)
        let recovery = MemoryRecovery()
        let controller = DataBackupController(model: f.model, recovery: recovery)
        try controller.prepareImport(data: incoming.encoded(), fileName: "incoming.json")

        // The timer is allowed to finish while its import preview is open.
        f.model.nextPhase()
        f.model.advanceTimer(by: 5)
        XCTAssertEqual(f.model.forest.events.count, 1)
        let justBeforeConfirmation = try f.model.makeBackup()
        controller.confirmRestore()
        XCTAssertEqual(recovery.saved.first, justBeforeConfirmation)
        XCTAssertEqual(try f.model.makeBackup().forest, incoming.forest)

        // Recreate both objects, as after closing and opening the app.
        let restarted = f.relaunch()
        let reopenedController = DataBackupController(model: restarted, recovery: recovery)
        XCTAssertTrue(reopenedController.recoveryAvailable)
        reopenedController.prepareUndo()
        XCTAssertTrue(reopenedController.review?.isUndo == true)
        XCTAssertEqual(reopenedController.review?.backup, justBeforeConfirmation)
        let unchanged = try state(restarted)
        reopenedController.cancelReview()
        XCTAssertEqual(try state(restarted), unchanged)
        reopenedController.prepareUndo()
        reopenedController.confirmRestore()
        XCTAssertNil(reopenedController.errorMessage)
        XCTAssertEqual(try restarted.makeBackup().forest, justBeforeConfirmation.forest)
        XCTAssertEqual(try restarted.makeBackup().settings, justBeforeConfirmation.settings)
        XCTAssertFalse(restarted.engine.isRunning)
        XCTAssertEqual(recovery.saved.count, 2)
        XCTAssertEqual(recovery.saved[1].forest, incoming.forest)
    }

    @MainActor
    func testSafetySnapshotFailurePreservesTheEntireLiveStateAndExactPreferenceBytes() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        let incoming = try populatedBackup(source)
        f.model.nextPhase()
        f.model.advanceTimer(by: 1)
        let before = try state(f.model)
        let rawBefore = f.persistedValues
        let recovery = MemoryRecovery()
        recovery.shouldFail = true
        let controller = DataBackupController(model: f.model, recovery: recovery)
        try controller.prepareImport(data: incoming.encoded(), fileName: "incoming.json")
        controller.confirmRestore()
        XCTAssertTrue(controller.errorMessage?.contains("安全副本磁盘不可写") == true)
        XCTAssertNotNil(controller.review)
        XCTAssertNil(controller.message)
        XCTAssertFalse(controller.isBusy)
        XCTAssertFalse(controller.recoveryAvailable)
        XCTAssertEqual(recovery.saveCalls, 1)
        XCTAssertEqual(try state(f.model), before)
        XCTAssertEqual(f.persistedValues, rawBefore)
    }

    @MainActor
    func testTruncatedUnknownVersionAndMalformedSettingsAreRejectedBeforePreparation() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        let valid = try populatedBackup(source).encoded()
        let before = try state(f.model)
        let rawBefore = f.persistedValues
        let recovery = MemoryRecovery()
        let controller = DataBackupController(model: f.model, recovery: recovery)
        var version = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        version["version"] = 99
        var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var settings = try XCTUnwrap(malformed["settings"] as? [String: Any])
        settings["eyeRest"] = ["intervalMinutes": "not a number", "restSeconds": 20]
        malformed["settings"] = settings
        for data in [Data(valid.prefix(valid.count / 2)), try JSONSerialization.data(withJSONObject: version),
                     try JSONSerialization.data(withJSONObject: malformed)] {
            XCTAssertThrowsError(try controller.prepareImport(data: data, fileName: "invalid.json"))
            XCTAssertNil(controller.review)
            XCTAssertEqual(try state(f.model), before)
            XCTAssertEqual(f.persistedValues, rawBefore)
            XCTAssertEqual(recovery.saveCalls, 0)
        }
    }

    @MainActor
    func testUnreadableOriginalCanBeRepairedAndItsExactBytesAndSettingsCanBeUndoneAfterRelaunch() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        f.model.stop()
        let corrupt = Data("unreadable original forest archive".utf8)
        f.defaults.set(corrupt, forKey: "forestProfiles.v1")
        let temporaryModel = f.relaunch()
        XCTAssertFalse(temporaryModel.forest.canSafelyReplace)
        XCTAssertThrowsError(try temporaryModel.makeBackup())
        XCTAssertEqual(temporaryModel.forest.rawArchiveData(), corrupt)
        let before = try temporaryModel.makeRecoverySnapshot()
        let directory = f.directory.appendingPathComponent("Recovery", isDirectory: true)
        let recovery = LocalBackupRecoveryStore(directory: directory)
        let controller = DataBackupController(model: temporaryModel, recovery: recovery)
        XCTAssertNotNil(controller.unreadableWarning)
        let incoming = try populatedBackup(source)
        try controller.prepareImport(data: incoming.encoded(), fileName: "valid.json")
        controller.confirmRestore()
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(try temporaryModel.makeBackup().forest, incoming.forest)
        XCTAssertEqual(try temporaryModel.makeBackup().settings, incoming.settings)
        XCTAssertTrue(temporaryModel.forest.canSafelyReplace)
        let safetyURL = try XCTUnwrap(recovery.latestURL)
        let reopenedRecovery = LocalBackupRecoveryStore(directory: directory)
        XCTAssertEqual(try reopenedRecovery.loadSnapshot(), before)
        XCTAssertEqual(try reopenedRecovery.loadSnapshot().rawOriginal, corrupt)
        XCTAssertThrowsError(try reopenedRecovery.loadLatest())
        XCTAssertThrowsError(try RestlingBackup.decode(BackupFileIO.read(safetyURL)))

        let restarted = f.relaunch()
        let reopenedController = DataBackupController(model: restarted, recovery: reopenedRecovery)
        reopenedController.prepareUndo()
        XCTAssertTrue(reopenedController.review?.isRawOriginal == true)
        XCTAssertNil(reopenedController.review?.incoming)
        reopenedController.confirmRestore()
        XCTAssertNil(reopenedController.errorMessage)
        XCTAssertFalse(restarted.forest.canSafelyReplace)
        XCTAssertEqual(restarted.forest.rawArchiveData(), corrupt)
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), corrupt)
        XCTAssertEqual(try restarted.makeRecoverySnapshot().settings, before.settings)
        XCTAssertEqual(restarted.forest.current.completedRests, 0)
        XCTAssertTrue(restarted.forest.events.isEmpty)
        XCTAssertNil(restarted.forest.latestRestReward)
        XCTAssertFalse(restarted.wantsRunning)
        // Undo itself first protects the repaired dataset, making the action reversible too.
        XCTAssertEqual(try reopenedRecovery.loadLatest().forest, incoming.forest)
    }

    @MainActor
    func testLocalRecoveryFilesArePrivateSurviveReconstructionAndKeepEarlierSnapshots() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let path = f.directory.appendingPathComponent("Backups", isDirectory: true)
        let store = LocalBackupRecoveryStore(directory: path)
        XCTAssertNil(store.latestURL)
        let original = try f.model.makeBackup()
        let firstURL = try store.save(original)
        XCTAssertEqual(try store.loadLatest(), original)
        let permissions = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber
        let filePermissions = try FileManager.default.attributesOfItem(atPath: firstURL.path)[.posixPermissions] as? NSNumber
        let pointerURL = path.appendingPathComponent("latest-recovery.json")
        let pointerPermissions = try FileManager.default.attributesOfItem(atPath: pointerURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        XCTAssertEqual(filePermissions?.intValue, 0o600)
        XCTAssertEqual(pointerPermissions?.intValue, 0o600)

        f.model.forest.renameCurrent("稍后的数据")
        let later = try f.model.makeBackup()
        let secondURL = try store.save(later)
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(try RestlingBackup.decode(BackupFileIO.read(firstURL)), original)
        let reopened = LocalBackupRecoveryStore(directory: path)
        XCTAssertEqual(reopened.latestURL, secondURL)
        XCTAssertEqual(try reopened.loadLatest(), later)
    }

    @MainActor
    func testLocalRecoveryRejectsEscapingOversizedFutureAndSymlinkPointers() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let path = f.directory.appendingPathComponent("Backups", isDirectory: true)
        let store = LocalBackupRecoveryStore(directory: path)
        let goodURL = try store.save(f.model.makeBackup())
        let pointerURL = path.appendingPathComponent("latest-recovery.json")
        let outside = f.directory.appendingPathComponent("Restling-before-outside.json")
        try f.model.makeBackup().encoded().write(to: outside)
        let link = path.appendingPathComponent("Restling-before-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let pointers: [Data] = [
            try JSONSerialization.data(withJSONObject: ["version": 1, "fileName": "../Restling-before-outside.json"]),
            try JSONSerialization.data(withJSONObject: ["version": 1, "fileName": outside.path]),
            try JSONSerialization.data(withJSONObject: ["version": 99, "fileName": goodURL.lastPathComponent]),
            try JSONSerialization.data(withJSONObject: ["version": 1, "fileName": link.lastPathComponent]),
            Data(repeating: 32, count: 4_097)
        ]
        for pointer in pointers {
            try pointer.write(to: pointerURL, options: .atomic)
            let reopened = LocalBackupRecoveryStore(directory: path)
            XCTAssertNil(reopened.latestURL)
            XCTAssertThrowsError(try reopened.loadLatest())
            XCTAssertTrue(FileManager.default.fileExists(atPath: goodURL.path))
        }
    }

    @MainActor
    func testUnwritableRecoveryLocationAbortsImportWithoutChangingCurrentData() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        let notDirectory = f.directory.appendingPathComponent("regular-file")
        try Data("not a directory".utf8).write(to: notDirectory)
        let recovery = LocalBackupRecoveryStore(directory: notDirectory)
        let controller = DataBackupController(model: f.model, recovery: recovery)
        let original = try state(f.model)
        let raw = f.persistedValues
        try controller.prepareImport(data: populatedBackup(source).encoded(), fileName: "incoming.json")
        controller.confirmRestore()
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(try state(f.model), original)
        XCTAssertEqual(f.persistedValues, raw)
        XCTAssertEqual(try Data(contentsOf: notDirectory), Data("not a directory".utf8))
        XCTAssertNil(recovery.latestURL)
    }

    @MainActor
    func testFileReaderRejectsALargerThanAllowedPhysicalFile() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let url = f.directory.appendingPathComponent("oversized.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(RestlingBackup.maxDataSize + 1))
        try handle.close()
        XCTAssertThrowsError(try BackupFileIO.read(url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("20 MB"))
        }
    }

    @MainActor
    func testRawSnapshotCodecIsLosslessAndCannotBeImportedAsAnOrdinaryBackup() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let raw = Data([0, 255, 42, 0, 128])
        let settings = BackupSettings(eyeRest: EyeRestSettings(intervalMinutes: 12, restSeconds: 25),
            reminders: ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 15),
            weatherChoice: "breezy", hasSeenOnboarding: true, automaticUpdateChecksEnabled: false)
        let snapshot = try RecoverySnapshot(rawOriginal: raw, settings: settings, createdAt: f.clock.date)
        let encoded = try snapshot.encoded()
        XCTAssertEqual(try RecoverySnapshot.decode(encoded), snapshot)
        XCTAssertEqual(try RecoverySnapshot.decode(encoded).rawOriginal, raw)
        XCTAssertTrue(snapshot.isRawOriginal)
        XCTAssertNil(snapshot.backup)
        XCTAssertThrowsError(try RestlingBackup.decode(encoded))

        let backup = try f.model.makeBackup()
        let ordinary = RecoverySnapshot(backup: backup)
        XCTAssertFalse(ordinary.isRawOriginal)
        XCTAssertNil(ordinary.rawOriginal)
        XCTAssertEqual(try RestlingBackup.decode(ordinary.encoded()), backup)
        XCTAssertEqual(try RecoverySnapshot.decode(ordinary.encoded()), ordinary)

        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        future["version"] = 99
        XCTAssertThrowsError(try RecoverySnapshot.decode(JSONSerialization.data(withJSONObject: future)))
        future["version"] = 1
        future["rawOriginal"] = "invalid base64 ?"
        XCTAssertThrowsError(try RecoverySnapshot.decode(JSONSerialization.data(withJSONObject: future)))
        XCTAssertThrowsError(try RecoverySnapshot(rawOriginal: raw, settings: settings,
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)))
    }

    @MainActor
    func testEmptyUnreadableOriginalCanBeRepairedAndUndoneWithoutLosingItsExactEmptyValue() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        f.model.stop()
        f.defaults.set(Data(), forKey: "forestProfiles.v1")
        let temporaryModel = f.relaunch()
        let recovery = LocalBackupRecoveryStore(directory: f.directory.appendingPathComponent("EmptyOriginal"))
        let controller = DataBackupController(model: temporaryModel, recovery: recovery)
        let incoming = try populatedBackup(source)
        try controller.prepareImport(data: incoming.encoded(), fileName: "valid.json")
        controller.confirmRestore()
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(try temporaryModel.makeBackup().forest, incoming.forest)
        XCTAssertEqual(try recovery.loadSnapshot().rawOriginal, Data())
        controller.prepareUndo()
        XCTAssertTrue(controller.review?.isRawOriginal == true)
        controller.confirmRestore()
        XCTAssertNil(controller.errorMessage)
        XCTAssertFalse(temporaryModel.forest.canSafelyReplace)
        XCTAssertEqual(temporaryModel.forest.rawArchiveData(), Data())
        XCTAssertEqual(f.defaults.data(forKey: "forestProfiles.v1"), Data())
        XCTAssertTrue(temporaryModel.forest.events.isEmpty)
        XCTAssertFalse(temporaryModel.engine.isRunning)
    }

    @MainActor
    func testRawSafetySnapshotFailureDoesNotChangeTheOriginalSettingsOrLiveTimer() async throws {
        let f = try Fixture(), source = try Fixture()
        defer { f.cleanup(); source.cleanup() }
        f.model.stop()
        let raw = Data("unreadable original".utf8)
        f.defaults.set(raw, forKey: "forestProfiles.v1")
        let temporaryModel = f.relaunch()
        temporaryModel.nextPhase()
        temporaryModel.advanceTimer(by: 1)
        let original = try state(temporaryModel)
        let persisted = f.persistedValues
        let recovery = SnapshotFailureRecovery()
        let controller = DataBackupController(model: temporaryModel, recovery: recovery)
        try controller.prepareImport(data: populatedBackup(source).encoded(), fileName: "valid.json")
        controller.confirmRestore()
        XCTAssertTrue(controller.errorMessage?.contains("测试快照保存失败") == true)
        XCTAssertEqual(recovery.saveCalls, 1)
        XCTAssertEqual(try state(temporaryModel), original)
        XCTAssertEqual(f.persistedValues, persisted)
        XCTAssertEqual(temporaryModel.forest.rawArchiveData(), raw)
        XCTAssertFalse(temporaryModel.forest.canSafelyReplace)
    }

    @MainActor
    func testNamedPipesAreRejectedBeforeEitherBackupOrPointerReadsCanBlock() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let fifo = f.directory.appendingPathComponent("selected-pipe.json")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        // This fallback releases a regressed blocking reader instead of hanging
        // the entire suite. Correct code rejects metadata before it is needed.
        let path = fifo.path
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let writer = Darwin.open(path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { Darwin.close(writer) }
        }
        XCTAssertThrowsError(try BackupFileIO.read(fifo)) { error in
            XCTAssertTrue(error.localizedDescription.contains("普通备份文件"))
        }

        let directory = f.directory.appendingPathComponent("Recovery", isDirectory: true)
        let recovery = LocalBackupRecoveryStore(directory: directory)
        let backupURL = try recovery.save(f.model.makeBackup())
        let pointer = directory.appendingPathComponent("latest-recovery.json")
        try FileManager.default.removeItem(at: pointer)
        XCTAssertEqual(mkfifo(pointer.path, 0o600), 0)
        let pointerPath = pointer.path
        let pointerBytes = try JSONSerialization.data(withJSONObject: [
            "version": 1, "fileName": backupURL.lastPathComponent
        ])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let writer = Darwin.open(pointerPath, O_WRONLY | O_NONBLOCK)
            if writer >= 0 {
                pointerBytes.withUnsafeBytes { bytes in
                    _ = Darwin.write(writer, bytes.baseAddress, bytes.count)
                }
                Darwin.close(writer)
            }
        }
        XCTAssertNil(recovery.latestURL)
        XCTAssertThrowsError(try recovery.loadSnapshot())
    }
}
