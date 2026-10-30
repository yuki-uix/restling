import Foundation

/// An explanation suitable for showing when local or imported forest data is invalid.
public enum ForestDataError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

/// Keep imported wall-clock dates inside the displayable Gregorian range.
/// Finite Double values alone may still be far outside Foundation formatters.
enum ForestDataValidation {
    static func validateDate(_ date: Date, field: String) throws {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= -62_135_596_800, seconds < 253_402_300_800 else {
            throw ForestDataError.invalid("\(field)超出有效日期范围（公历 1 至 9999 年）。")
        }
    }
}

/// One terminal outcome for a real rest attempt. Its ID is the timer's stable
/// rest-session ID, so retries and restored timer snapshots remain idempotent.
public struct ForestRestEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Outcome: String, Codable, CaseIterable, Sendable {
        case completed, skipped
    }

    public let id: UUID
    public let profileID: UUID
    public let occurredAt: Date
    public let configuredSeconds: TimeInterval
    public let outcome: Outcome

    public init(id: UUID = UUID(), profileID: UUID, occurredAt: Date = Date(),
                configuredSeconds: TimeInterval, outcome: Outcome) {
        self.id = id
        self.profileID = profileID
        self.occurredAt = occurredAt
        self.configuredSeconds = configuredSeconds
        self.outcome = outcome
    }

    public func validate() throws {
        try ForestDataValidation.validateDate(occurredAt, field: "休息记录的发生时间")
        guard configuredSeconds.isFinite, configuredSeconds > 0, configuredSeconds <= 86_400 else {
            throw ForestDataError.invalid("休息记录的配置时长无效。")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, occurredAt, configuredSeconds, outcome
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        profileID = try values.decode(UUID.self, forKey: .profileID)
        occurredAt = try values.decode(Date.self, forKey: .occurredAt)
        configuredSeconds = try values.decode(TimeInterval.self, forKey: .configuredSeconds)
        outcome = try values.decode(Outcome.self, forKey: .outcome)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(profileID, forKey: .profileID)
        try values.encode(occurredAt, forKey: .occurredAt)
        try values.encode(configuredSeconds, forKey: .configuredSeconds)
        try values.encode(outcome, forKey: .outcome)
    }
}
