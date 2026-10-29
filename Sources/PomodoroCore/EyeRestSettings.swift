import Foundation

/// The eye-rest rhythm is independent of legacy Pomodoro settings. Every break,
/// including the engine's internal long-break phase, lasts the same number of seconds.
public struct EyeRestSettings: Codable, Equatable, Sendable {
    public var intervalMinutes: Int {
        didSet { intervalMinutes = min(120, max(1, intervalMinutes)) }
    }
    public var restSeconds: Int {
        didSet { restSeconds = min(180, max(5, restSeconds)) }
    }

    public init(intervalMinutes: Int = 20, restSeconds: Int = 20) {
        self.intervalMinutes = min(120, max(1, intervalMinutes))
        self.restSeconds = min(180, max(5, restSeconds))
    }

    public var configuration: PomodoroConfiguration {
        PomodoroConfiguration(focusDuration: Double(intervalMinutes) * 60,
                              shortBreakDuration: Double(restSeconds),
                              longBreakDuration: Double(restSeconds),
                              roundsBeforeLongBreak: 4)
    }

    private enum CodingKeys: String, CodingKey {
        case intervalMinutes, restSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(intervalMinutes: try values.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 20,
                  restSeconds: try values.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 20)
    }
}
