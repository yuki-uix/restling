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
    var onUpdate: (() -> Void)?
    var onTransition: ((PomodoroPhase) -> Void)?

    private let settingsKey = "eyeRestSettings.v1"
    private let defaults: UserDefaults
    private var ticker: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var resumeAfterWake = false
    private var timingActivity: NSObjectProtocol?
    private struct RestGrowthSession {
        let id = UUID()
        let profileID: UUID
        let duration: TimeInterval
    }
    private var restGrowthSession: RestGrowthSession?

    init(smokeTest: Bool = false, resumingRemaining remaining: TimeInterval? = nil,
         completedFocusSessions: Int = 0, resumingPhase: PomodoroPhase = .focus,
         resumeRunning: Bool = true, forest: ForestStore? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let forest {
            self.forest = forest
        } else if smokeTest {
            // Integration previews must never earn progress in a personal forest.
            self.forest = ForestStore(defaults: UserDefaults(suiteName: "breaktime.smoke.\(UUID().uuidString)")!)
        } else {
            self.forest = ForestStore(defaults: defaults)
        }
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
        // An explicit local update can hand off the active session and count.
        // Ordinary launches continue to start ready, as before.
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
            if resumingPhase != .focus { beginRestGrowth(phase: resumingPhase) }
            publishUpdate()
        }
        let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
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
        !isSleeping && (previewRemaining != nil || (engine.phase != .focus && engine.isRunning))
    }
    var restRemaining: TimeInterval { previewRemaining ?? engine.remaining }
    var isPreview: Bool { previewRemaining != nil }
    var restForestProfile: ForestProfile {
        guard !isPreview, let rest = restGrowthSession,
              let owner = forest.profiles.first(where: { $0.id == rest.profileID }) else { return forest.current }
        return owner
    }
    var toggleTitle: String { engine.isRunning ? "暂停提醒" : hasStarted ? "继续提醒" : "开启休息提醒" }
    var phaseActionTitle: String { engine.phase == .focus ? "现在休息" : "提前结束休息" }

    func toggleRunning() {
        tick()
        previewRemaining = nil
        if engine.isRunning { engine.pause() }
        else { engine.start(); hasStarted = true }
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
    }

    func nextPhase() {
        previewRemaining = nil
        // Skipping is deliberately different from completing a full break.
        restGrowthSession = nil
        engine.skipPhase()
        if engine.phase != .focus { beginRestGrowth(phase: engine.phase) }
        engine.start()
        hasStarted = true
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
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
        previewRemaining = nil
        restGrowthSession = nil
        engine.reset()
        hasStarted = false
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
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
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
    }

    func applyEyeRestSettings(_ settings: EyeRestSettings) {
        eyeRestSettings = settings
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
        }
        previewRemaining = nil
        restGrowthSession = nil
        engine.updateConfiguration(settings.configuration)
        hasStarted = false
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
    }

    func preview() {
        guard !isSleeping else { return }
        tick()
        // The current session keeps its remaining time while the preview is visible.
        previewRemaining = 20
        lastTick = ProcessInfo.processInfo.systemUptime
        publishUpdate()
    }

    func willSleep() {
        guard !isSleeping else { return }
        tick()
        resumeAfterWake = engine.isRunning
        engine.pause()
        previewRemaining = nil
        isSleeping = true
        publishUpdate()
    }

    func didWake() {
        guard isSleeping else { return }
        isSleeping = false
        lastTick = ProcessInfo.processInfo.systemUptime
        if resumeAfterWake { engine.start() }
        resumeAfterWake = false
        publishUpdate()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        if let timingActivity {
            ProcessInfo.processInfo.endActivity(timingActivity)
            self.timingActivity = nil
        }
    }

    private func publishUpdate() {
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
        onUpdate?()
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - lastTick)
        lastTick = now
        advanceTimer(by: elapsed)
    }

    // This also provides a deterministic path for verifying rest rewards without
    // speeding up the real timer or modifying a user's forest.
    func advanceTimer(by elapsed: TimeInterval) {
        guard !isSleeping, elapsed.isFinite, elapsed > 0 else { return }
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
                        _ = forest.completeRest(profileID: rest.profileID, id: rest.id, seconds: rest.duration)
                    }
                    restGrowthSession = nil
                } else {
                    beginRestGrowth(phase: phase)
                }
                onTransition?(phase)
            }
        } else { return }
        publishUpdate()
    }

    private func beginRestGrowth(phase: PomodoroPhase) {
        restGrowthSession = RestGrowthSession(profileID: forest.current.id,
            duration: phase == .longBreak ? engine.configuration.longBreakDuration : engine.configuration.shortBreakDuration)
    }
}
