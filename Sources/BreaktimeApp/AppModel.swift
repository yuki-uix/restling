import AppKit
import Combine
import PomodoroCore

extension PomodoroPhase {
    var title: String {
        switch self {
        case .focus: return "用眼间隔"
        case .shortBreak, .longBreak: return "放松眼睛"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "timer"
        case .shortBreak, .longBreak: return "leaf.fill"
        }
    }
}

func clockText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds)))
    if total >= 3600 {
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
    return String(format: "%02d:%02d", total / 60, total % 60)
}

@MainActor
final class AppModel: NSObject, ObservableObject {
    let forest: ForestStore
    @Published private(set) var engine: PomodoroEngine
    @Published private(set) var eyeRestSettings: EyeRestSettings
    @Published private(set) var hasStarted = false
    @Published private(set) var previewRemaining: TimeInterval?
    @Published private(set) var isSleeping = false
    @Published private(set) var reminderPreferences: ReminderPreferences
    @Published private(set) var wantsRunning = false
    @Published private(set) var isLocked = false
    @Published private(set) var isDisplaySleeping = false
    @Published private(set) var isIdle = false
    @Published private(set) var doNotDisturbUntil: Date?
    @Published private(set) var snoozeUntil: Date?
    @Published private(set) var returnGraceUntil: Date?
    @Published private(set) var pauseReason: ReminderPauseReason?
    @Published private(set) var prewarningDismissed = false
    var onUpdate: (() -> Void)?
    var onTransition: ((PomodoroPhase) -> Void)?
    var onSound: ((RestSoundCue) -> Void)?
    var onUserInteraction: (() -> Void)?

    private let settingsKey = "eyeRestSettings.v1"
    private let defaults: UserDefaults
    private var ticker: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private let now: () -> Date
    private let fixedCalendar: Calendar?
    private let smokeTest: Bool
    private var lastIdleSeconds: TimeInterval = 0
    private var previousBlockers: Set<ReminderPauseReason> = []
    private var lastSnapshotUptime = -Double.infinity
    private var timingActivity: NSObjectProtocol?
    private struct RestGrowthSession: Codable {
        let id: UUID
        let profileID: UUID
        let duration: TimeInterval
    }
    private var restGrowthSession: RestGrowthSession?

    private struct SessionArchive: Codable {
        let version: Int
        let configuration: PomodoroConfiguration
        let phase: PomodoroPhase
        let remaining: TimeInterval
        let completedFocusSessions: Int
        let hasStarted: Bool
        let wantsRunning: Bool
        let rest: RestGrowthSession?
        let doNotDisturbUntil: Date?
        let snoozeUntil: Date?
    }

    private let preferencesKey = "reminderPreferences.v1"
    private let sessionKey = "reminderSession.v1"

    init(smokeTest: Bool = false, resumingRemaining remaining: TimeInterval? = nil,
         completedFocusSessions: Int = 0, resumingPhase: PomodoroPhase = .focus,
         resumeRunning: Bool = true, forest: ForestStore? = nil, defaults suppliedDefaults: UserDefaults? = nil,
         now: @escaping () -> Date = Date.init, calendar: Calendar? = nil,
         startsTicker: Bool = true, restoreSession: Bool = true) {
        let defaults = suppliedDefaults ?? (smokeTest
            ? UserDefaults(suiteName: "breaktime.smoke.\(UUID().uuidString)")! : .standard)
        self.defaults = defaults
        self.now = now
        fixedCalendar = calendar
        self.smokeTest = smokeTest
        var preferences = defaults.data(forKey: "reminderPreferences.v1")
            .flatMap { try? JSONDecoder().decode(ReminderPreferences.self, from: $0) } ?? ReminderPreferences()
        if smokeTest {
            preferences = ReminderPreferences(idlePauseEnabled: false, returnGraceSeconds: 0,
                                               prewarningSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)
        }
        reminderPreferences = preferences
        self.forest = forest ?? ForestStore(defaults: defaults)
        let settings: EyeRestSettings
        if let data = defaults.data(forKey: "eyeRestSettings.v1"),
           let saved = try? JSONDecoder().decode(EyeRestSettings.self, from: data) {
            settings = saved
        } else {
            // Deliberately start the new eye-rest product at 20 min / 20 sec.
            // Preserve the old Pomodoro key so the earlier mode is recoverable.
            settings = EyeRestSettings()
            if !smokeTest, let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: "eyeRestSettings.v1")
            }
        }
        eyeRestSettings = settings
        let config: PomodoroConfiguration
        if smokeTest {
            config = PomodoroConfiguration(focusDuration: 2, shortBreakDuration: 2,
                                            longBreakDuration: 3, roundsBeforeLongBreak: 2)
        } else {
            config = settings.configuration
        }
        engine = PomodoroEngine(configuration: config)
        super.init()
        // An explicit local handoff takes precedence over a persisted session.
        let duration: TimeInterval
        switch resumingPhase {
        case .focus: duration = config.focusDuration
        case .shortBreak: duration = config.shortBreakDuration
        case .longBreak: duration = config.longBreakDuration
        }
        if !smokeTest, let remaining, remaining.isFinite,
           remaining > 0, remaining <= duration {
            engine = PomodoroEngine(configuration: config, phase: resumingPhase, remaining: remaining,
                                    completedFocusSessions: completedFocusSessions, isRunning: resumeRunning)
            hasStarted = true
            wantsRunning = resumeRunning
            if resumingPhase != .focus { beginRestGrowth(phase: resumingPhase) }
        } else if !smokeTest, restoreSession,
                  let data = defaults.data(forKey: sessionKey),
                  let saved = try? JSONDecoder().decode(SessionArchive.self, from: data),
                  saved.version == 1, saved.configuration == config,
                  saved.remaining.isFinite, saved.remaining > 0,
                  saved.remaining <= Self.duration(of: saved.phase, configuration: config),
                  (0...1_000_000).contains(saved.completedFocusSessions),
                  (!saved.wantsRunning || saved.hasStarted) {
            engine = PomodoroEngine(configuration: config, phase: saved.phase, remaining: saved.remaining,
                completedFocusSessions: saved.completedFocusSessions, isRunning: false)
            hasStarted = saved.hasStarted
            wantsRunning = saved.wantsRunning
            if saved.phase != .focus, let rest = saved.rest,
               rest.duration == Self.duration(of: saved.phase, configuration: config),
               self.forest.profiles.contains(where: { $0.id == rest.profileID }) {
                restGrowthSession = rest
            } else if saved.phase != .focus { restartFocus() }
            if let deadline = saved.doNotDisturbUntil, deadline > now(),
               deadline.timeIntervalSince(now()) < 7 * 86_400 { doNotDisturbUntil = deadline }
            if let deadline = saved.snoozeUntil, deadline > now(),
               deadline.timeIntervalSince(now()) <= 300 { snoozeUntil = deadline }
            else if saved.snoozeUntil != nil { restartFocus() }
            if wantsRunning { addReturnGrace() }
        }
        reconcileEligibility()
        if startsTicker {
            let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(tick),
                              userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    var currentRound: Int {
        let count = engine.configuration.roundsBeforeLongBreak
        if engine.phase == .focus { return engine.completedFocusSessions % count + 1 }
        return max(1, (engine.completedFocusSessions - 1) % count + 1)
    }

    var totalDuration: TimeInterval {
        switch engine.phase {
        case .focus: return engine.configuration.focusDuration
        case .shortBreak: return engine.configuration.shortBreakDuration
        case .longBreak: return engine.configuration.longBreakDuration
        }
    }

    var progress: Double { min(1, max(0, 1 - engine.remaining / totalDuration)) }
    var showingRest: Bool {
        pauseReason == nil && (previewRemaining != nil || (engine.phase != .focus && engine.isRunning))
    }
    var restRemaining: TimeInterval { previewRemaining ?? engine.remaining }
    var isPreview: Bool { previewRemaining != nil }
    var restForestProfile: ForestProfile {
        guard !isPreview, let rest = restGrowthSession,
              let owner = forest.profiles.first(where: { $0.id == rest.profileID }) else { return forest.current }
        return owner
    }
    var toggleTitle: String { wantsRunning ? "暂停提醒" : hasStarted ? "继续提醒" : "开启休息提醒" }
    var phaseActionTitle: String { engine.phase == .focus ? "现在休息" : "提前结束休息" }
    var isSnoozing: Bool { snoozeUntil.map { $0 > now() } ?? false }
    var canRestNow: Bool { pauseReason == nil }
    var canPreview: Bool { pauseReason == nil && !isSleeping && !isLocked }
    var isPrewarningVisible: Bool {
        reminderPreferences.prewarningSeconds > 0 && !prewarningDismissed && !isPreview &&
        pauseReason == nil && engine.isRunning && engine.phase == .focus &&
        engine.remaining <= Double(reminderPreferences.prewarningSeconds) && !isSnoozing
    }
    var displayedRemaining: TimeInterval {
        if let deadline = snoozeUntil { return max(0, deadline.timeIntervalSince(now())) }
        return engine.remaining
    }
    var statusDescription: String {
        if let reason = pauseReason {
            switch reason {
            case .sleeping: return "系统休眠中"
            case .displaySleeping: return "显示器休眠，提醒已暂停"
            case .locked: return "锁屏或用户会话暂停，提醒已暂停"
            case .idle: return "离席暂停 · 返回后稍等再继续"
            case .outsideSchedule:
                if let date = reminderPreferences.nextAllowedStart(after: now(), calendar: activeCalendar) {
                    return "非提醒时段 · 下次 \(date.formatted(.dateTime.weekday().hour().minute()))"
                }
                return "非提醒时段 · 请在设置中选择提醒日期"
            case .doNotDisturb:
                let end = doNotDisturbUntil?.formatted(.dateTime.hour().minute()) ?? ""
                return wantsRunning ? "临时勿扰 · \(end) 自动恢复" : "临时勿扰至 \(end) · 提醒仍暂停"
            case .returnGrace:
                guard wantsRunning else { return "提醒已手动暂停" }
                return "返回缓冲 · \(Int(ceil(max(0, returnGraceUntil?.timeIntervalSince(now()) ?? 0)))) 秒后继续"
            }
        }
        if !hasStarted { return "尚未开启休息提醒" }
        if !wantsRunning { return "提醒已手动暂停" }
        if isSnoozing { return "本次休息已推迟 · \(clockText(displayedRemaining)) 后提醒" }
        return engine.phase == .focus ? "提醒运行中" : "休息中 · 结束后自动返回"
    }
    var menuBarTitle: String {
        if pauseReason == .doNotDisturb {
            return "勿扰至 \(doNotDisturbUntil?.formatted(.dateTime.hour().minute()) ?? "")"
        }
        if pauseReason == .outsideSchedule { return "非提醒时段" }
        if pauseReason == .idle { return "离席暂停" }
        if pauseReason == .locked { return "锁屏暂停" }
        if pauseReason == .displaySleeping { return "屏幕休眠" }
        if pauseReason == .returnGrace { return "稍等 \(Int(ceil(max(0, returnGraceUntil?.timeIntervalSince(now()) ?? 0))))秒" }
        return clockText(displayedRemaining)
    }
    private var activeCalendar: Calendar { fixedCalendar ?? .current }

    func toggleRunning() {
        onUserInteraction?()
        tick()
        previewRemaining = nil
        wantsRunning.toggle()
        if wantsRunning { hasStarted = true }
        reconcileEligibility()
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func nextPhase() {
        let intendedToStartRest = engine.phase == .focus
        onUserInteraction?()
        reconcileEligibility()
        guard canRestNow else { return }
        if intendedToStartRest && engine.phase != .focus {
            // The snooze deadline may have opened the requested break during
            // reconciliation. Preserve this click's intent instead of skipping it.
            publishUpdate(forceSave: true)
            return
        }
        previewRemaining = nil
        snoozeUntil = nil
        // Skipping is deliberately different from completing a full break.
        restGrowthSession = nil
        engine.skipPhase()
        if engine.phase != .focus { beginRestGrowth(phase: engine.phase) }
        engine.start()
        hasStarted = true
        wantsRunning = true
        prewarningDismissed = false
        if engine.phase != .focus { emitSound(.start) }
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func dismissRest() {
        if previewRemaining != nil {
            previewRemaining = nil
            publishUpdate()
        } else if engine.phase != .focus {
            nextPhase()
        }
    }

    func reset() {
        onUserInteraction?()
        previewRemaining = nil
        restGrowthSession = nil
        engine.reset()
        hasStarted = false
        wantsRunning = false
        snoozeUntil = nil
        prewarningDismissed = false
        lastTick = ProcessInfo.processInfo.systemUptime
        reconcileEligibility()
        publishUpdate(forceSave: true)
    }

    func apply(_ config: PomodoroConfiguration) {
        // Compatibility path for the earlier generic timer. The eye-rest UI
        // saves through applyEyeRestSettings and never overwrites this archive.
        if let encoded = try? JSONEncoder().encode(config) {
            defaults.set(encoded, forKey: "pomodoroConfiguration.v1")
        }
        previewRemaining = nil
        restGrowthSession = nil
        engine.updateConfiguration(config)
        hasStarted = false
        wantsRunning = false
        snoozeUntil = nil
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func applyEyeRestSettings(_ settings: EyeRestSettings) {
        onUserInteraction?()
        eyeRestSettings = settings
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
        }
        previewRemaining = nil
        restGrowthSession = nil
        engine.updateConfiguration(settings.configuration)
        hasStarted = false
        wantsRunning = false
        snoozeUntil = nil
        prewarningDismissed = false
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func preview() {
        onUserInteraction?()
        reconcileEligibility()
        guard canPreview else { return }
        tick()
        // The current session keeps its remaining time while the preview is visible.
        previewRemaining = 20
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
    }

    func willSleep() {
        guard !isSleeping else { return }
        previewRemaining = nil
        isSleeping = true
        reconcileEligibility()
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func didWake() {
        guard isSleeping else { return }
        isSleeping = false
        lastTick = ProcessInfo.processInfo.systemUptime
        if wantsRunning { addReturnGrace() }
        reconcileEligibility()
        publishUpdate(forceSave: true)
    }

    func stop() {
        persistSession(force: true)
        ticker?.invalidate()
        ticker = nil
        if let timingActivity {
            ProcessInfo.processInfo.endActivity(timingActivity)
            self.timingActivity = nil
        }
    }

    private func publishUpdate(forceSave: Bool = false) {
        // Keep reminders timely with the settings window closed, while permitting
        // normal system sleep. A menu-bar-only app otherwise qualifies for App Nap.
        let needsActivity = !isSleeping && (engine.isRunning || isPreview)
        if needsActivity && timingActivity == nil {
            timingActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "用眼间隔计时与放松提醒")
        } else if !needsActivity, let timingActivity {
            ProcessInfo.processInfo.endActivity(timingActivity)
            self.timingActivity = nil
        }
        persistSession(force: forceSave)
        onUpdate?()
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - lastTick)
        lastTick = now
        processLiveTick(elapsed: elapsed)
    }

    /// Production timer path: do not replay an unseen break across a delayed tick.
    func processLiveTick(elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        if let preview = previewRemaining {
            advanceTimer(by: min(elapsed, preview))
            return
        }
        // A stalled process must not replay unseen break cycles. Ordinary
        // engine simulations remain deterministic; only live ticks use this gate.
        if elapsed > 30 {
            if wantsRunning {
                snoozeUntil = nil
                restartFocus()
                addReturnGrace()
            }
            reconcileEligibility()
            publishUpdate(forceSave: true)
        } else {
            // A late focus tick may open a break, but may not consume that
            // break before its overlay has ever been presented.
            advanceTimer(by: min(elapsed, previewRemaining ?? engine.remaining))
        }
    }

    // This also provides a deterministic path for verifying rest rewards without
    // speeding up the real timer or modifying a user's forest.
    func advanceTimer(by elapsed: TimeInterval) {
        let changedEligibility = reconcileEligibility()
        guard !isSleeping, elapsed.isFinite, elapsed > 0 else { return }
        guard pauseReason == nil else { publishUpdate(); return }
        // Eligibility has just changed (e.g. a work window started or a snooze
        // expired). No elapsed time belongs to the newly resumed phase yet.
        if changedEligibility { publishUpdate(); return }
        if let preview = previewRemaining {
            previewRemaining = preview > elapsed ? preview - elapsed : nil
        } else if engine.isRunning {
            if engine.phase != .focus && restGrowthSession == nil {
                beginRestGrowth(phase: engine.phase)
            }
            let transitions = engine.advance(by: elapsed)
            for phase in transitions {
                if phase == .focus {
                    if let rest = restGrowthSession {
                        let credited = forest.completeRest(profileID: rest.profileID, id: rest.id, seconds: rest.duration)
                        if credited { emitSound(.end) }
                    }
                    restGrowthSession = nil
                    prewarningDismissed = false
                } else {
                    beginRestGrowth(phase: phase)
                    emitSound(.start)
                }
                onTransition?(phase)
            }
        } else { return }
        publishUpdate()
    }

    private func beginRestGrowth(phase: PomodoroPhase) {
        restGrowthSession = RestGrowthSession(id: UUID(), profileID: forest.current.id,
            duration: phase == .longBreak ? engine.configuration.longBreakDuration : engine.configuration.shortBreakDuration)
    }

    func applyReminderPreferences(_ preferences: ReminderPreferences) {
        onUserInteraction?()
        tick()
        reminderPreferences = preferences
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferencesKey) }
        if !preferences.idlePauseEnabled { isIdle = false }
        reconcileEligibility()
        publishUpdate(forceSave: true)
    }

    func snooze(minutes: Int) {
        onUserInteraction?()
        reconcileEligibility()
        guard [3, 5].contains(minutes), wantsRunning, pauseReason == nil,
              !isPreview, isPrewarningVisible || showingRest || isSnoozing else { return }
        restartFocus()
        snoozeUntil = now().addingTimeInterval(Double(minutes * 60))
        prewarningDismissed = true
        reconcileEligibility()
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func dismissPrewarning() {
        prewarningDismissed = true
        publishUpdate()
    }

    func pauseFor(minutes: Int) {
        onUserInteraction?()
        guard [30, 60].contains(minutes) else { return }
        doNotDisturbUntil = now().addingTimeInterval(Double(minutes * 60))
        reconcileEligibility()
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func endDoNotDisturb() {
        onUserInteraction?()
        doNotDisturbUntil = nil
        reconcileEligibility()
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate(forceSave: true)
    }

    func updatePresence(locked: Bool, idleSeconds: TimeInterval, displaySleeping: Bool = false) {
        let oldLocked = isLocked, oldIdle = isIdle, oldDisplaySleeping = isDisplaySleeping
        let wasUnavailable = isLocked || isIdle || isDisplaySleeping
        isLocked = locked
        isDisplaySleeping = displaySleeping
        lastIdleSeconds = idleSeconds.isFinite ? max(0, idleSeconds) : 0
        // Being still is expected during a break; never require a key press to
        // finish one. The next focus interval may pause if the person stays away.
        if !locked && !displaySleeping && !isSleeping {
            isIdle = reminderPreferences.idlePauseEnabled &&
                (engine.phase == .focus || isIdle) && lastIdleSeconds >= Double(reminderPreferences.idleThresholdSeconds)
        }
        if wasUnavailable && !isLocked && !isIdle && !isDisplaySleeping && wantsRunning { addReturnGrace() }
        reconcileEligibility()
        if oldLocked != isLocked || oldIdle != isIdle || oldDisplaySleeping != isDisplaySleeping {
            lastTick = ProcessInfo.processInfo.systemUptime
        }
        publishUpdate(forceSave: wasUnavailable != (isLocked || isIdle || isDisplaySleeping))
    }

    /// Re-evaluate wall-clock restrictions without advancing active-use time.
    func refreshEligibility() {
        reconcileEligibility()
        publishUpdate()
    }

    private func addReturnGrace() {
        guard reminderPreferences.returnGraceSeconds > 0 else { return }
        returnGraceUntil = now().addingTimeInterval(Double(reminderPreferences.returnGraceSeconds))
    }

    @discardableResult
    private func reconcileEligibility() -> Bool {
        let date = now()
        if let deadline = doNotDisturbUntil, deadline <= date { doNotDisturbUntil = nil }
        if let deadline = returnGraceUntil, deadline <= date { returnGraceUntil = nil }
        var blockers = Set<ReminderPauseReason>()
        if isSleeping { blockers.insert(.sleeping) }
        if isDisplaySleeping { blockers.insert(.displaySleeping) }
        if isLocked { blockers.insert(.locked) }
        if isIdle { blockers.insert(.idle) }
        if !reminderPreferences.scheduleAllows(at: date, calendar: activeCalendar) { blockers.insert(.outsideSchedule) }
        if doNotDisturbUntil != nil { blockers.insert(.doNotDisturb) }
        if returnGraceUntil != nil { blockers.insert(.returnGrace) }
        let sleepReasons: Set<ReminderPauseReason> = [.sleeping, .displaySleeping]
        if !previousBlockers.intersection(sleepReasons).isEmpty,
           blockers.intersection(sleepReasons).isEmpty,
           let deadline = snoozeUntil, deadline <= date {
            // A reminder postponed before sleep must not be replayed after an
            // absence. A deadline that is still in the future remains valid.
            snoozeUntil = nil
            restartFocus()
        }
        let freshReasons: Set<ReminderPauseReason> = [.locked, .idle, .outsideSchedule, .doNotDisturb]
        if !blockers.subtracting(previousBlockers).intersection(freshReasons).isEmpty {
            restartFocus()
            snoozeUntil = nil
        }
        let changed = blockers != previousBlockers
        previousBlockers = blockers
        pauseReason = ReminderPauseReason.allCases.first(where: blockers.contains)
        if !blockers.isEmpty {
            engine.pause()
            previewRemaining = nil
            return changed
        }
        if let deadline = snoozeUntil {
            engine.pause()
            if deadline <= date {
                snoozeUntil = nil
                if wantsRunning {
                    engine.skipPhase()
                    beginRestGrowth(phase: engine.phase)
                    engine.start()
                    onTransition?(engine.phase)
                    emitSound(.start)
                }
                return true
            }
            return changed
        }
        if wantsRunning { engine.start() } else { engine.pause() }
        return changed
    }

    private func restartFocus() {
        restGrowthSession = nil
        prewarningDismissed = false
        engine = PomodoroEngine(configuration: engine.configuration, phase: .focus,
            remaining: engine.configuration.focusDuration,
            completedFocusSessions: engine.completedFocusSessions, isRunning: false)
    }

    private func emitSound(_ cue: RestSoundCue) {
        guard pauseReason == nil, !isPreview, !smokeTest,
              cue == .start ? reminderPreferences.startSoundEnabled : reminderPreferences.endSoundEnabled else { return }
        onSound?(cue)
    }

    private func persistSession(force: Bool) {
        guard !smokeTest else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard force || uptime - lastSnapshotUptime >= 2 else { return }
        let archive = SessionArchive(version: 1, configuration: engine.configuration,
            phase: engine.phase, remaining: engine.remaining, completedFocusSessions: engine.completedFocusSessions,
            hasStarted: hasStarted, wantsRunning: wantsRunning, rest: restGrowthSession,
            doNotDisturbUntil: doNotDisturbUntil, snoozeUntil: snoozeUntil)
        if let data = try? JSONEncoder().encode(archive) {
            defaults.set(data, forKey: sessionKey)
            lastSnapshotUptime = uptime
        }
    }

    private static func duration(of phase: PomodoroPhase, configuration: PomodoroConfiguration) -> TimeInterval {
        switch phase {
        case .focus: return configuration.focusDuration
        case .shortBreak: return configuration.shortBreakDuration
        case .longBreak: return configuration.longBreakDuration
        }
    }
}

enum ReminderPauseReason: String, CaseIterable, Hashable {
    case sleeping, locked, displaySleeping, doNotDisturb, outsideSchedule, idle, returnGrace
}

enum RestSoundCue: Equatable { case start, end }
