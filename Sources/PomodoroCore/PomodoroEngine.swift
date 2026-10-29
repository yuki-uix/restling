import Foundation

/// User-editable intervals, normalized at creation and decoding boundaries.
public struct PomodoroConfiguration: Codable, Equatable, Sendable {
    public let focusDuration: TimeInterval
    public let shortBreakDuration: TimeInterval
    public let longBreakDuration: TimeInterval
    public let roundsBeforeLongBreak: Int

    public init(
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        roundsBeforeLongBreak: Int = 4
    ) {
        self.focusDuration = Self.normalized(focusDuration, fallback: 25 * 60)
        self.shortBreakDuration = Self.normalized(shortBreakDuration, fallback: 5 * 60)
        self.longBreakDuration = Self.normalized(longBreakDuration, fallback: 15 * 60)
        self.roundsBeforeLongBreak = min(12, max(1, roundsBeforeLongBreak))
    }

    private static func normalized(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return fallback }
        return min(24 * 60 * 60, max(1, value))
    }

    private enum CodingKeys: String, CodingKey {
        case focusDuration, shortBreakDuration, longBreakDuration, roundsBeforeLongBreak
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            focusDuration: try values.decodeIfPresent(TimeInterval.self, forKey: .focusDuration) ?? 25 * 60,
            shortBreakDuration: try values.decodeIfPresent(TimeInterval.self, forKey: .shortBreakDuration) ?? 5 * 60,
            longBreakDuration: try values.decodeIfPresent(TimeInterval.self, forKey: .longBreakDuration) ?? 15 * 60,
            roundsBeforeLongBreak: try values.decodeIfPresent(Int.self, forKey: .roundsBeforeLongBreak) ?? 4
        )
    }
}

public enum PomodoroPhase: String, Codable, Equatable, Sendable {
    case focus
    case shortBreak
    case longBreak
}

/// A deterministic timer state machine. The caller supplies monotonic elapsed time.
/// No wall-clock, UI, persistence or background scheduling is hidden in the engine.
public struct PomodoroEngine: Sendable {
    public private(set) var configuration: PomodoroConfiguration
    public private(set) var phase: PomodoroPhase = .focus
    public private(set) var remaining: TimeInterval
    public private(set) var isRunning = false
    public private(set) var completedFocusSessions = 0

    public init(configuration: PomodoroConfiguration = PomodoroConfiguration()) {
        self.configuration = configuration
        self.remaining = configuration.focusDuration
    }

    /// Restore an explicit local handoff without replaying or earning sessions.
    public init(configuration: PomodoroConfiguration, phase: PomodoroPhase,
                remaining: TimeInterval, completedFocusSessions: Int, isRunning: Bool) {
        self.configuration = configuration
        self.phase = phase
        let duration: TimeInterval
        switch phase {
        case .focus: duration = configuration.focusDuration
        case .shortBreak: duration = configuration.shortBreakDuration
        case .longBreak: duration = configuration.longBreakDuration
        }
        self.remaining = remaining.isFinite ? min(duration, max(0.001, remaining)) : duration
        self.completedFocusSessions = min(1_000_000, max(0, completedFocusSessions))
        self.isRunning = isRunning
    }

    public mutating func start() {
        isRunning = true
    }

    public mutating func pause() {
        isRunning = false
    }

    public mutating func reset() {
        phase = .focus
        remaining = configuration.focusDuration
        isRunning = false
        completedFocusSessions = 0
    }

    /// Skip a phase without recording an unfinished focus session as completed.
    /// Running/paused state is preserved, so a paused skip cannot start a timer.
    public mutating func skipPhase() {
        enter(phase == .focus ? .shortBreak : .focus)
    }

    public mutating func updateConfiguration(_ configuration: PomodoroConfiguration) {
        self.configuration = configuration
        reset()
    }

    /// Advance by an actual elapsed interval, returning newly entered phases in order.
    /// Delayed ticks retain their overshoot instead of lengthening every session.
    /// Invalid deltas are ignored; one update catches up at most 24 hours to bound work
    /// if a caller accidentally supplies an epoch timestamp or an extreme clock jump.
    @discardableResult
    public mutating func advance(by elapsed: TimeInterval) -> [PomodoroPhase] {
        guard isRunning, elapsed.isFinite, elapsed > 0 else { return [] }
        var unconsumed = min(elapsed, 24 * 60 * 60)
        var transitions: [PomodoroPhase] = []

        while unconsumed >= remaining {
            unconsumed -= remaining
            if phase == .focus {
                completedFocusSessions += 1
                let next: PomodoroPhase = completedFocusSessions % configuration.roundsBeforeLongBreak == 0
                    ? .longBreak
                    : .shortBreak
                enter(next)
            } else {
                enter(.focus)
            }
            transitions.append(phase)
        }

        remaining -= unconsumed
        return transitions
    }

    private mutating func enter(_ phase: PomodoroPhase) {
        self.phase = phase
        switch phase {
        case .focus: remaining = configuration.focusDuration
        case .shortBreak: remaining = configuration.shortBreakDuration
        case .longBreak: remaining = configuration.longBreakDuration
        }
    }
}
