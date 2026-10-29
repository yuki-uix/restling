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
    private var updateObservation: AnyCancellable?
    private var startupUpdateTask: Task<Void, Never>?
    private var updateTimer: Timer?
    private var overlay: RestOverlayController!
    private var phaseItem: NSMenuItem!
    private var forestItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var nextItem: NSMenuItem!
    private var lastStatusTitle = ""
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")

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
        model = AppModel(smokeTest: smokeTest, resumingRemaining: resumeSeconds,
                         completedFocusSessions: completed, resumingPhase: phase,
                         resumeRunning: !args.contains("--resume-paused"))
        updater = UpdateChecker(configuration: smokeTest ? nil : UpdateConfiguration.fromBundle())
        overlay = RestOverlayController(model: model)
        createApplicationMenu()
        createMenu()
        updateObservation = updater.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        model.onUpdate = { [weak self] in self?.refresh() }
        model.onTransition = { [weak self] phase in
            if self?.smokeTest == true { print("SMOKE transition=\(phase.title)"); fflush(stdout) }
            if phase != .focus { NSSound(named: "Glass")?.play() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
        showMainWindow()
        if !smokeTest {
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

    private func createApplicationMenu() {
        // Standard responder actions also enable Command-Q/W and text-field
        // copy/paste in this programmatically-created accessory application.
        let main = NSMenu()
        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "Restling")
        appMenu.addItem(item("打开 Restling…", #selector(showMainWindow), key: ","))
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
        menu.addItem(.separator())
        menu.addItem(item("森林休息预览（20 秒）", #selector(preview)))
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
        let text = clockText(engine.remaining)
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
        statusItem.button?.toolTip = "Restling · \(engine.phase.title) · \(engine.isRunning ? "提醒已开启" : model.hasStarted ? "提醒已暂停" : "尚未开始")"
        if updater.shouldShowBanner, let release = updater.availableRelease {
            statusItem.button?.toolTip?.append(" · 新版本 \(release.version.description)")
            updateItem.title = "发现新版本 \(release.version.description)…"
        } else { updateItem.title = "检查更新…" }
        phaseItem.title = "\(engine.phase == .focus ? "距下次休息" : "休息剩余") · \(text)"
        let forest = model.forest.current
        forestItem.title = "\(forest.name) · \(forest.trees.count) 棵树 · 再休息 \(forest.restsUntilTree) 次长成新树"
        toggleItem.title = model.toggleTitle
        nextItem.title = model.phaseActionTitle
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
            window.contentView = NSHostingView(rootView: MainView(model: model, updater: updater,
                onShowUpdates: { [weak self] in self?.showUpdates() }, onboardingEnabled: !smokeTest))
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
    @objc private func willSleep() { model.willSleep() }
    @objc private func didWake() { model.didWake() }
    @objc private func screensChanged() { overlay.rebuildIfVisible() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        startupUpdateTask?.cancel()
        updateTimer?.invalidate()
        updateObservation?.cancel()
        overlay.close(restoreFocus: false)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
