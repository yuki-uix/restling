import Foundation

/// Only portable preferences belong in a backup. Login items, running timers,
/// temporary deadlines and cached update metadata remain local to the Mac.
public struct BackupSettings: Codable, Equatable, Sendable {
    public let eyeRest: EyeRestSettings
    public let reminders: ReminderPreferences
    public let weatherChoice: String
    public let hasSeenOnboarding: Bool
    public let automaticUpdateChecksEnabled: Bool

    public init(eyeRest: EyeRestSettings = EyeRestSettings(),
                reminders: ReminderPreferences = ReminderPreferences(),
                weatherChoice: String = "automatic", hasSeenOnboarding: Bool = false,
                automaticUpdateChecksEnabled: Bool = true) {
        self.eyeRest = eyeRest
        self.reminders = reminders
        self.weatherChoice = weatherChoice
        self.hasSeenOnboarding = hasSeenOnboarding
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
    }

    public func validate() throws {
        try StrictRhythm(eyeRest).validate()
        try StrictReminders(reminders).validate()
        guard weatherChoice == "automatic" || ForestWeather.allCases.contains(where: { $0.rawValue == weatherChoice }) else {
            throw ForestDataError.invalid("备份中的森林天气设置无效。")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case eyeRest, reminders, weatherChoice, hasSeenOnboarding, automaticUpdateChecksEnabled
    }

    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // These DTOs deliberately do not use the app's forgiving preference
            // decoders. A backup must not silently clamp or invent settings.
            let rhythm = try values.decode(StrictRhythm.self, forKey: .eyeRest)
            let reminder = try values.decode(StrictReminders.self, forKey: .reminders)
            try rhythm.validate()
            try reminder.validate()
            eyeRest = EyeRestSettings(intervalMinutes: rhythm.intervalMinutes, restSeconds: rhythm.restSeconds)
            reminders = reminder.preferences
            weatherChoice = try values.decode(String.self, forKey: .weatherChoice)
            hasSeenOnboarding = try values.decode(Bool.self, forKey: .hasSeenOnboarding)
            automaticUpdateChecksEnabled = try values.decode(Bool.self, forKey: .automaticUpdateChecksEnabled)
            try validate()
        } catch let error as ForestDataError {
            throw error
        } catch {
            throw ForestDataError.invalid("备份设置不完整或字段类型有误。")
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(StrictRhythm(eyeRest), forKey: .eyeRest)
        try values.encode(StrictReminders(reminders), forKey: .reminders)
        try values.encode(weatherChoice, forKey: .weatherChoice)
        try values.encode(hasSeenOnboarding, forKey: .hasSeenOnboarding)
        try values.encode(automaticUpdateChecksEnabled, forKey: .automaticUpdateChecksEnabled)
    }

    private struct StrictRhythm: Codable {
        let intervalMinutes: Int
        let restSeconds: Int

        init(_ value: EyeRestSettings) {
            intervalMinutes = value.intervalMinutes
            restSeconds = value.restSeconds
        }

        func validate() throws {
            guard (1...120).contains(intervalMinutes), (5...180).contains(restSeconds) else {
                throw ForestDataError.invalid("备份中的用眼间隔或休息时长超出有效范围。")
            }
        }
    }

    private struct StrictReminders: Codable {
        let scheduleEnabled: Bool
        let weekdays: [Int]
        let startMinute: Int
        let endMinute: Int
        let idlePauseEnabled: Bool
        let idleThresholdSeconds: Int
        let returnGraceSeconds: Int
        let prewarningSeconds: Int
        let startSoundEnabled: Bool
        let endSoundEnabled: Bool

        init(_ value: ReminderPreferences) {
            scheduleEnabled = value.scheduleEnabled
            weekdays = value.weekdays.sorted()
            startMinute = value.startMinute
            endMinute = value.endMinute
            idlePauseEnabled = value.idlePauseEnabled
            idleThresholdSeconds = value.idleThresholdSeconds
            returnGraceSeconds = value.returnGraceSeconds
            prewarningSeconds = value.prewarningSeconds
            startSoundEnabled = value.startSoundEnabled
            endSoundEnabled = value.endSoundEnabled
        }

        var preferences: ReminderPreferences {
            ReminderPreferences(scheduleEnabled: scheduleEnabled, weekdays: Set(weekdays),
                startMinute: startMinute, endMinute: endMinute, idlePauseEnabled: idlePauseEnabled,
                idleThresholdSeconds: idleThresholdSeconds, returnGraceSeconds: returnGraceSeconds,
                prewarningSeconds: prewarningSeconds, startSoundEnabled: startSoundEnabled,
                endSoundEnabled: endSoundEnabled)
        }

        func validate() throws {
            guard weekdays.allSatisfy({ (1...7).contains($0) }),
                  Set(weekdays).count == weekdays.count,
                  !scheduleEnabled || !weekdays.isEmpty else {
                throw ForestDataError.invalid("备份中的提醒日期无效，开启工作时段时需要至少一个提醒日。")
            }
            guard (0...1_439).contains(startMinute), (0...1_439).contains(endMinute),
                  (60...3_600).contains(idleThresholdSeconds),
                  (0...300).contains(returnGraceSeconds), (0...60).contains(prewarningSeconds) else {
                throw ForestDataError.invalid("备份中的提醒时段、离席或预告设置超出有效范围。")
            }
        }
    }
}

/// A human-readable, local backup format. Dates use JSONEncoder's default
/// seconds since 2001-01-01 UTC, matching local archives without precision loss.
public struct RestlingBackup: Codable, Equatable, Sendable {
    public static let maxDataSize = 20 * 1_024 * 1_024

    public let format: String
    public let version: Int
    public let createdAt: Date
    public let forest: ForestArchive
    public let settings: BackupSettings

    public init(forest: ForestArchive, settings: BackupSettings, createdAt: Date = Date()) throws {
        format = "restling-backup"
        version = 1
        self.createdAt = createdAt
        self.forest = forest
        self.settings = settings
        try validate()
    }

    public func validate() throws {
        guard format == "restling-backup" else {
            throw ForestDataError.invalid("这个文件不是 Restling 备份。")
        }
        guard version == 1 else {
            throw ForestDataError.invalid("暂不支持这个备份版本，请使用兼容的 Restling 版本。")
        }
        try ForestDataValidation.validateDate(createdAt, field: "备份的创建时间")
        try forest.validate()
        try settings.validate()
    }

    public static func decode(_ data: Data) throws -> RestlingBackup {
        guard data.count <= maxDataSize else {
            throw ForestDataError.invalid("备份文件超过 20 MB，无法导入。")
        }
        do {
            let result = try JSONDecoder().decode(RestlingBackup.self, from: data)
            try result.validate()
            return result
        } catch let error as ForestDataError {
            throw error
        } catch {
            throw ForestDataError.invalid("备份文件不完整或内容已损坏，当前森林没有更改。")
        }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(self)
        } catch let error as ForestDataError {
            throw error
        } catch {
            throw ForestDataError.invalid("备份暂时无法生成，请重试。")
        }
        guard data.count <= Self.maxDataSize else {
            throw ForestDataError.invalid("备份数据超过 20 MB，无法导出。")
        }
        return data
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, createdAt, forest, settings
    }

    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            format = try values.decode(String.self, forKey: .format)
            version = try values.decode(Int.self, forKey: .version)
            guard format == "restling-backup" else {
                throw ForestDataError.invalid("这个文件不是 Restling 备份。")
            }
            guard version == 1 else {
                throw ForestDataError.invalid("暂不支持这个备份版本，请使用兼容的 Restling 版本。")
            }
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            forest = try values.decode(ForestArchive.self, forKey: .forest)
            settings = try values.decode(BackupSettings.self, forKey: .settings)
            try validate()
        } catch let error as ForestDataError {
            throw error
        } catch {
            throw ForestDataError.invalid("备份文件不完整或字段类型有误。")
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(format, forKey: .format)
        try values.encode(version, forKey: .version)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(forest, forKey: .forest)
        try values.encode(settings, forKey: .settings)
    }
}
