import Foundation

/// Local reminder eligibility and presentation preferences, separate from the
/// eye-rest rhythm. Weekdays use Calendar's numbering: Sunday = 1.
public struct ReminderPreferences: Codable, Equatable, Sendable {
    public var scheduleEnabled: Bool
    public var weekdays: Set<Int> {
        didSet { weekdays = Set(weekdays.filter { (1...7).contains($0) }) }
    }
    public var startMinute: Int {
        didSet { startMinute = min(1_439, max(0, startMinute)) }
    }
    public var endMinute: Int {
        didSet { endMinute = min(1_439, max(0, endMinute)) }
    }
    public var idlePauseEnabled: Bool
    public var idleThresholdSeconds: Int {
        didSet { idleThresholdSeconds = min(3_600, max(60, idleThresholdSeconds)) }
    }
    public var returnGraceSeconds: Int {
        didSet { returnGraceSeconds = min(300, max(0, returnGraceSeconds)) }
    }
    /// Zero disables the advance warning.
    public var prewarningSeconds: Int {
        didSet { prewarningSeconds = min(60, max(0, prewarningSeconds)) }
    }
    public var startSoundEnabled: Bool
    public var endSoundEnabled: Bool

    public init(scheduleEnabled: Bool = false, weekdays: Set<Int> = [2, 3, 4, 5, 6],
                startMinute: Int = 540, endMinute: Int = 1_080,
                idlePauseEnabled: Bool = true, idleThresholdSeconds: Int = 300,
                returnGraceSeconds: Int = 30, prewarningSeconds: Int = 10,
                startSoundEnabled: Bool = true, endSoundEnabled: Bool = true) {
        self.scheduleEnabled = scheduleEnabled
        self.weekdays = Set(weekdays.filter { (1...7).contains($0) })
        self.startMinute = min(1_439, max(0, startMinute))
        self.endMinute = min(1_439, max(0, endMinute))
        self.idlePauseEnabled = idlePauseEnabled
        self.idleThresholdSeconds = min(3_600, max(60, idleThresholdSeconds))
        self.returnGraceSeconds = min(300, max(0, returnGraceSeconds))
        self.prewarningSeconds = min(60, max(0, prewarningSeconds))
        self.startSoundEnabled = startSoundEnabled
        self.endSoundEnabled = endSoundEnabled
    }

    /// Start is inclusive and end is exclusive. An overnight window belongs to
    /// its starting weekday; equal start/end means the selected calendar day.
    public func scheduleAllows(at date: Date, calendar: Calendar = .current) -> Bool {
        guard scheduleEnabled else { return true }
        guard !weekdays.isEmpty, date.timeIntervalSinceReferenceDate.isFinite else { return false }
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute == endMinute { return weekdays.contains(weekday) }
        if startMinute < endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        if minute >= startMinute { return weekdays.contains(weekday) }
        let previousWeekday = (weekday + 5) % 7 + 1
        return minute < endMinute && weekdays.contains(previousWeekday)
    }

    /// Earliest allowed instant at or after `date`, within the next eight local
    /// calendar days. Returns `date` when already allowed, nil for no selected
    /// days. Calendar matching handles missing and repeated DST wall times.
    public func nextAllowedStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        if scheduleAllows(at: date, calendar: calendar) { return date }
        guard !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        var candidates: [Date] = []
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            if startMinute == endMinute {
                if day >= date { candidates.append(day) }
                continue
            }
            for repeatedTime: Calendar.RepeatedTimePolicy in [.first, .last] {
                guard let candidate = calendar.date(bySettingHour: startMinute / 60,
                    minute: startMinute % 60, second: 0, of: day,
                    matchingPolicy: .nextTime, repeatedTimePolicy: repeatedTime, direction: .forward),
                    candidate >= date, calendar.isDate(candidate, inSameDayAs: day),
                    scheduleAllows(at: candidate, calendar: calendar) else { continue }
                candidates.append(candidate)
            }
        }
        return candidates.min()
    }

    private enum CodingKeys: String, CodingKey {
        case scheduleEnabled, weekdays, startMinute, endMinute, idlePauseEnabled
        case idleThresholdSeconds, returnGraceSeconds, prewarningSeconds
        case startSoundEnabled, endSoundEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReminderPreferences()
        // A malformed individual preference recovers independently; unrelated
        // choices remain intact and numeric bounds still pass through init.
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decode(T.self, forKey: key)) ?? fallback
        }
        self.init(scheduleEnabled: value(.scheduleEnabled, defaults.scheduleEnabled),
                  weekdays: value(.weekdays, defaults.weekdays),
                  startMinute: value(.startMinute, defaults.startMinute),
                  endMinute: value(.endMinute, defaults.endMinute),
                  idlePauseEnabled: value(.idlePauseEnabled, defaults.idlePauseEnabled),
                  idleThresholdSeconds: value(.idleThresholdSeconds, defaults.idleThresholdSeconds),
                  returnGraceSeconds: value(.returnGraceSeconds, defaults.returnGraceSeconds),
                  prewarningSeconds: value(.prewarningSeconds, defaults.prewarningSeconds),
                  startSoundEnabled: value(.startSoundEnabled, defaults.startSoundEnabled),
                  endSoundEnabled: value(.endSoundEnabled, defaults.endSoundEnabled))
    }
}
