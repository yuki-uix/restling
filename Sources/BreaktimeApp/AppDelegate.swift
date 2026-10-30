import AppKit
import SwiftUI
import PomodoroCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var updateWindow: NSWindow?
    private var updater: UpdateChecker!
    private var dataBackups: DataBackupController!
    private var updateObservation: AnyCancellable?
    private var startupUpdateTask: Task<Void, Never>?
    private var updateTimer: Timer?
    private var overlay: RestOverlayController!
    private var prewarning: PrewarningController!
    private var presence: PresenceMonitor?
    private let loginItem = LoginItemController()
    private var phaseItem: NSMenuItem!
    private var forestItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var nextItem: NSMenuItem!
    private var dndItem: NSMenuItem!
    private var resumeDNDItem: NSMenuItem!
    private var snoozeItem: NSMenuItem!
    private var previewItem: NSMenuItem!
    private var lastStatusTitle = ""
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")
    private let uiTest = CommandLine.arguments.contains("--ui-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let resumeIndex = args.firstIndex(of: "--resume-seconds") ?? args.firstIndex(of: "--resume-focus-seconds")
        let resumeSeconds = resumeIndex.flatMap { index in
            index + 1 < args.count ? Double(args[index + 1]) : nil
        }
        let completedIndex = args.firstIndex(of: "--resume-completed-focus")
        let completed = completedIndex.flatMap { index in
            index + 1 < args.count ? Int(args[index + 1]) : nil
        } ?? 0
        let phaseIndex = args.firstIndex(of: "--resume-phase")
        let phase = phaseIndex.flatMap { index in
            index + 1 < args.count ? PomodoroPhase(rawValue: args[index + 1]) : nil
        } ?? .focus
        let testDefaults = uiTest ? UserDefaults(suiteName: "restling.ui.\(UUID().uuidString)") : nil
        if let testDefaults { prepareUITestData(defaults: testDefaults, arguments: args) }
        model = AppModel(smokeTest: smokeTest, resumingRemaining: resumeSeconds,
                         completedFocusSessions: completed, resumingPhase: phase,
                         resumeRunning: !args.contains("--resume-paused"), defaults: testDefaults)
        updater = UpdateChecker(configuration: smokeTest || uiTest ? nil : UpdateConfiguration.fromBundle(),
                                defaults: testDefaults ?? .standard)
        let recovery = smokeTest || uiTest ? LocalBackupRecoveryStore(directory:
            FileManager.default.temporaryDirectory.appendingPathComponent("Restling-QA-\(UUID().uuidString)", isDirectory: true)) : nil
        dataBackups = DataBackupController(model: model, updater: updater, recovery: recovery)
        overlay = RestOverlayController(model: model)
        prewarning = PrewarningController(model: model)
        createApplicationMenu()
        createMenu()
        updateObservation = updater.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        model.onUpdate = { [weak self] in self?.refresh() }
        model.onTransition = { [weak self] phase in
            if self?.smokeTest == true { print("SMOKE transition=\(phase.title)"); fflush(stdout) }
        }
        model.onSound = { cue in NSSound(named: cue == .start ? "Glass" : "Tink")?.play() }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !smokeTest {
            presence = PresenceMonitor { [weak self] locked, idleSeconds, displaySleeping in
                self?.model.updatePresence(locked: locked, idleSeconds: idleSeconds, displaySleeping: displaySleeping)
            }
            model.onUserInteraction = { [weak self] in self?.presence?.confirmUserInteraction() }
            // Sample current lock/idle state before showing any restored overlay.
            presence?.start()
        }
        refresh()
        showMainWindow()
        if !smokeTest && !uiTest {
            startupUpdateTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.updater.checkForUpdates()
            }
            // The checker enforces its own persisted 24-hour limit. This timer
            // also covers an app left open for days and never wakes a sleeping Mac.
            updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.updater.checkForUpdates() }
            }
        }
        if smokeTest {
            print("SMOKE launched screens=\(NSScreen.screens.count)"); fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.model.toggleRunning() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 17) { [weak self] in
                let forest = self?.model.forest.current
                print("SMOKE finished rests=\(forest?.completedRests ?? -1) trees=\(forest?.trees.count ?? -1)")
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }

    /// Disposable fixtures are available only inside the already isolated UI
    /// test mode. Normal launches never seed a forest or change preferences.
    private func prepareUITestData(defaults: UserDefaults, arguments: [String]) {
        let preferences = ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 0,
                                             startSoundEnabled: false, endSoundEnabled: false)
        defaults.set(try? JSONEncoder().encode(preferences), forKey: "reminderPreferences.v1")
        guard let index = arguments.firstIndex(of: "--ui-test-rests"), index + 1 < arguments.count,
              let count = Int(arguments[index + 1]), (0...200).contains(count) else { return }
        var profile = ForestProfile(name: "生态验收森林")
        let date = Date(timeIntervalSince1970: 1_793_347_200)
        for number in 0..<count {
            let eligible = ForestSpecies.allCases.filter { profile.isUnlocked($0) }
            profile.selectedSpecies = eligible[(number / 3) % eligible.count]
            profile.recordRest(id: UUID(), seconds: 20, date: date.addingTimeInterval(Double(number)))
        }
        if let speciesIndex = arguments.firstIndex(of: "--ui-test-species"), speciesIndex + 1 < arguments.count,
           let species = ForestSpecies(rawValue: arguments[speciesIndex + 1]), profile.isUnlocked(species) {
            profile.selectedSpecies = species
        }
        if let archive = try? ForestArchive(profiles: [profile], activeProfileID: profile.id),
           let data = try? JSONEncoder().encode(archive) {
            defaults.set(data, forKey: "forestProfiles.v1")
        }
    }

    private func createApplicationMenu() {
        // Standard responder actions also enable Command-Q/W and text-field
        // copy/paste in this programmatically-created accessory application.
        let main = NSMenu()
        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "Restling")
        appMenu.addItem(item("打开 Restling…", #selector(showMainWindow), key: ","))
        appMenu.addItem(item("提醒设置…", #selector(showReminderSettings)))
        appMenu.addItem(item("数据与备份…", #selector(showDataBackup)))
        appMenu.addItem(item("林地手记…", #selector(showForestEcology)))
        appMenu.addItem(item("检查更新…", #selector(showUpdates)))
        appMenu.addItem(item("关闭窗口", #selector(closeMainWindow), key: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出 Restling", #selector(quit), key: "q"))
        appRoot.submenu = appMenu
        main.addItem(appRoot)
        let editRoot = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                      ("复制", "copy:", "c"), ("粘贴", "paste:", "v"),
                                      ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editRoot.submenu = edit
        main.addItem(editRoot)
        NSApp.mainMenu = main
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        phaseItem.isEnabled = false
        menu.addItem(phaseItem)
        forestItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        forestItem.isEnabled = false
        menu.addItem(forestItem)
        menu.addItem(.separator())
        toggleItem = item("开启休息提醒", #selector(toggleRunning))
        menu.addItem(toggleItem)
        nextItem = item("现在休息", #selector(nextPhase))
        menu.addItem(nextItem)
        menu.addItem(item("重新开始用眼间隔", #selector(reset)))
        snoozeItem = NSMenuItem(title: "推迟本次休息", action: nil, keyEquivalent: "")
        let later = NSMenu()
        later.addItem(item("3 分钟后休息", #selector(snoozeThree)))
        later.addItem(item("5 分钟后休息", #selector(snoozeFive)))
        snoozeItem.submenu = later
        menu.addItem(snoozeItem)
        dndItem = NSMenuItem(title: "临时勿扰", action: nil, keyEquivalent: "")
        let quiet = NSMenu()
        quiet.addItem(item("勿扰 30 分钟", #selector(pauseThirty)))
        quiet.addItem(item("勿扰 1 小时", #selector(pauseSixty)))
        resumeDNDItem = item("结束临时勿扰", #selector(endDoNotDisturb))
        quiet.addItem(resumeDNDItem)
        dndItem.submenu = quiet
        menu.addItem(dndItem)
        menu.addItem(.separator())
        previewItem = item("森林休息预览（20 秒）", #selector(preview))
        menu.addItem(previewItem)
        menu.addItem(item("提醒设置…", #selector(showReminderSettings)))
        menu.addItem(item("数据与备份…", #selector(showDataBackup)))
        menu.addItem(item("林地手记…", #selector(showForestEcology)))
        menu.addItem(item("打开 Restling…", #selector(showMainWindow), key: ","))
        updateItem = item("检查更新…", #selector(showUpdates))
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(item("退出 Restling", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func refresh() {
        let engine = model.engine
        let text = model.menuBarTitle
        if text != lastStatusTitle {
            statusItem.button?.title = text
            lastStatusTitle = text
        }
        let symbol = updater.shouldShowBanner ? "arrow.down.circle.fill" :
            (!engine.isRunning && model.hasStarted ? "pause.circle" : engine.phase.symbol)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: engine.phase.title)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.toolTip = "Restling · \(model.statusDescription)"
        if updater.shouldShowBanner, let release = updater.availableRelease {
            statusItem.button?.toolTip?.append(" · 新版本 \(release.version.description)")
            updateItem.title = "发现新版本 \(release.version.description)…"
        } else { updateItem.title = "检查更新…" }
        phaseItem.title = model.statusDescription
        let forest = model.forest.current
        forestItem.title = "\(forest.name) · \(forest.trees.count) 棵树 · 再休息 \(forest.restsUntilTree) 次长成新树"
        toggleItem.title = model.toggleTitle
        nextItem.title = model.phaseActionTitle
        nextItem.isEnabled = model.canRestNow
        snoozeItem.isEnabled = model.canRestNow && !model.isPreview &&
            (model.isPrewarningVisible || model.showingRest || model.isSnoozing)
        previewItem.isEnabled = model.canPreview
        resumeDNDItem.isEnabled = model.doNotDisturbUntil != nil
        dndItem.title = model.doNotDisturbUntil == nil ? "临时勿扰" : model.menuBarTitle
        prewarning.synchronize()
        let wasVisible = overlay.isVisible
        overlay.synchronize()
        if smokeTest && wasVisible != overlay.isVisible {
            print("SMOKE overlays=\(overlay.windowCount) phase=\(engine.phase.title)"); fflush(stdout)
        }
    }

    @objc private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 740),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Restling · 休息森林"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainView(model: model, updater: updater, loginItem: loginItem,
                backupController: dataBackups,
                onShowUpdates: { [weak self] in self?.showUpdates() }, onboardingEnabled: !smokeTest && !uiTest))
            window.center()
            mainWindow = window
        }
        // A visible break already has the keyboard focus and a settings window stays beneath it.
        if !overlay.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func showUpdates() {
        if updateWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Restling · 应用更新"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: UpdateCenterView(checker: updater,
                onClose: { [weak window] in window?.orderOut(nil) }))
            window.center()
            updateWindow = window
        }
        if !overlay.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            updateWindow?.makeKeyAndOrderFront(nil)
        }
        Task { [weak self] in await self?.updater.checkForUpdates(manually: true) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
    @objc private func toggleRunning() { model.toggleRunning() }
    @objc private func closeMainWindow() {
        if overlay.isVisible { model.dismissRest() }
        else { (NSApp.keyWindow ?? mainWindow)?.performClose(nil) }
    }
    @objc private func nextPhase() { model.nextPhase() }
    @objc private func reset() { model.reset() }
    @objc private func preview() { model.preview() }
    @objc private func pauseThirty() { model.pauseFor(minutes: 30) }
    @objc private func pauseSixty() { model.pauseFor(minutes: 60) }
    @objc private func endDoNotDisturb() { model.endDoNotDisturb() }
    @objc private func snoozeThree() { model.snooze(minutes: 3) }
    @objc private func snoozeFive() { model.snooze(minutes: 5) }
    @objc private func showReminderSettings() {
        showMainWindow()
        NotificationCenter.default.post(name: .init("Restling.showReminderSettings"), object: nil)
    }
    @objc private func showDataBackup() {
        showMainWindow()
        NotificationCenter.default.post(name: .init("Restling.showDataBackup"), object: nil)
    }
    @objc private func showForestEcology() {
        showMainWindow()
        NotificationCenter.default.post(name: .init("Restling.showForestEcology"), object: nil)
    }
    @objc private func willSleep() { model.willSleep() }
    @objc private func didWake() { model.didWake() }
    @objc private func screensChanged() {
        overlay.rebuildIfVisible()
        prewarning.close()
        prewarning.synchronize()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        presence?.stop()
        prewarning.close()
        startupUpdateTask?.cancel()
        updateTimer?.invalidate()
        updateObservation?.cancel()
        overlay.close(restoreFocus: false)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
