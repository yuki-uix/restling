import Foundation
import XCTest
@testable import PomodoroCore

final class RestlingBackupTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000.123_456)

    private func fixture() throws -> RestlingBackup {
        var profile = ForestProfile(name: "窗边的森林")
        let restID = UUID()
        profile.recordRest(id: restID, seconds: 20, date: date)
        let events = [
            ForestRestEvent(id: restID, profileID: profile.id, occurredAt: date,
                            configuredSeconds: 20, outcome: .completed),
            ForestRestEvent(profileID: profile.id, occurredAt: date.addingTimeInterval(31.75),
                            configuredSeconds: 45, outcome: .skipped)
        ]
        let forest = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                       events: events, recordingStartedAt: date)
        let reminders = ReminderPreferences(scheduleEnabled: true, weekdays: [6], startMinute: 1_320,
            endMinute: 360, idlePauseEnabled: false, idleThresholdSeconds: 120, returnGraceSeconds: 15,
            prewarningSeconds: 30, startSoundEnabled: false, endSoundEnabled: true)
        let settings = BackupSettings(eyeRest: EyeRestSettings(intervalMinutes: 35, restSeconds: 45),
            reminders: reminders, weatherChoice: "breezy", hasSeenOnboarding: true,
            automaticUpdateChecksEnabled: false)
        return try RestlingBackup(forest: forest, settings: settings, createdAt: date.addingTimeInterval(1_000))
    }

    private func object() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture().encoded()) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func assertRejected(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try RestlingBackup.decode(data(object)), file: file, line: line) { error in
            XCTAssertTrue(error is ForestDataError, file: file, line: line)
            XCTAssertFalse(error.localizedDescription.isEmpty, file: file, line: line)
        }
    }

    func testFullBackupRoundTripPreservesForestSettingsIDsAndFractionalDates() throws {
        let backup = try fixture()
        let encoded = try backup.encoded()
        XCTAssertEqual(try RestlingBackup.decode(encoded), backup)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(raw["format"] as? String, "restling-backup")
        XCTAssertEqual(raw["version"] as? Int, 1)
        XCTAssertEqual(raw["createdAt"] as? Double, backup.createdAt.timeIntervalSinceReferenceDate)
        let settings = try XCTUnwrap(raw["settings"] as? [String: Any])
        XCTAssertEqual(Set(settings.keys), ["eyeRest", "reminders", "weatherChoice", "hasSeenOnboarding", "automaticUpdateChecksEnabled"])
        XCTAssertEqual(backup.settings.weatherChoice, "breezy")
        XCTAssertFalse(backup.settings.automaticUpdateChecksEnabled)
    }

    func testUnknownFormatVersionsAndMalformedFilesReturnExplainedErrors() throws {
        let original = try object()
        for (key, value) in [("format", "another-app" as Any), ("version", 2 as Any)] {
            var altered = original
            altered[key] = value
            try assertRejected(altered)
        }
        for bytes in [Data(), Data("{broken".utf8), Data([0xFF, 0xFE]), Data("[]".utf8)] {
            XCTAssertThrowsError(try RestlingBackup.decode(bytes)) { error in
                XCTAssertTrue(error is ForestDataError)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testEveryPortableSettingIsRequiredRatherThanDefaultedOnImport() throws {
        let original = try object()
        let settings = try XCTUnwrap(original["settings"] as? [String: Any])
        for key in settings.keys {
            var altered = original, changed = settings
            changed.removeValue(forKey: key)
            altered["settings"] = changed
            try assertRejected(altered)
        }
        for group in ["eyeRest", "reminders"] {
            let fields = try XCTUnwrap(settings[group] as? [String: Any])
            for key in fields.keys {
                var altered = original, changedSettings = settings, changedFields = fields
                changedFields.removeValue(forKey: key)
                changedSettings[group] = changedFields
                altered["settings"] = changedSettings
                try assertRejected(altered)
            }
        }
    }

    func testWrongPreferenceTypesCannotBeSilentlyReplaced() throws {
        let original = try object()
        let settings = try XCTUnwrap(original["settings"] as? [String: Any])
        for (group, field, wrong) in [
            ("eyeRest", "intervalMinutes", "20" as Any),
            ("reminders", "scheduleEnabled", "true" as Any),
            ("reminders", "weekdays", ["6"] as Any),
            ("reminders", "startSoundEnabled", 1 as Any),
            ("reminders", "startMinute", true as Any)
        ] {
            var altered = original, changedSettings = settings
            var fields = try XCTUnwrap(settings[group] as? [String: Any])
            fields[field] = wrong
            changedSettings[group] = fields
            altered["settings"] = changedSettings
            try assertRejected(altered)
        }
    }

    func testOutOfRangeSettingsAreRejectedInsteadOfClamped() throws {
        let original = try object()
        let settings = try XCTUnwrap(original["settings"] as? [String: Any])
        let cases: [(String, String, [Int])] = [
            ("eyeRest", "intervalMinutes", [0, 121]), ("eyeRest", "restSeconds", [4, 181]),
            ("reminders", "startMinute", [-1, 1_440]), ("reminders", "endMinute", [-1, 1_440]),
            ("reminders", "idleThresholdSeconds", [59, 3_601]),
            ("reminders", "returnGraceSeconds", [-1, 301]), ("reminders", "prewarningSeconds", [-1, 61])
        ]
        for (group, field, values) in cases {
            for wrong in values {
                var altered = original, changedSettings = settings
                var fields = try XCTUnwrap(settings[group] as? [String: Any])
                fields[field] = wrong
                changedSettings[group] = fields
                altered["settings"] = changedSettings
                try assertRejected(altered)
            }
        }
        for days in [[0], [8], [6, 6], []] {
            var altered = original, changedSettings = settings
            var fields = try XCTUnwrap(settings["reminders"] as? [String: Any])
            fields["weekdays"] = days
            changedSettings["reminders"] = fields
            altered["settings"] = changedSettings
            try assertRejected(altered)
        }
        var unknownWeather = original, changedSettings = settings
        changedSettings["weatherChoice"] = "storm"
        unknownWeather["settings"] = changedSettings
        try assertRejected(unknownWeather)
    }

    func testAllExistingWeatherChoicesAndDisabledEmptyScheduleCanRoundTrip() throws {
        let forest = try fixture().forest
        for weather in ["automatic"] + ForestWeather.allCases.map(\.rawValue) {
            let preferences = ReminderPreferences(scheduleEnabled: false, weekdays: [], startMinute: 0,
                endMinute: 1_439, idleThresholdSeconds: 60, returnGraceSeconds: 0, prewarningSeconds: 60)
            let settings = BackupSettings(eyeRest: EyeRestSettings(intervalMinutes: 1, restSeconds: 5),
                                           reminders: preferences, weatherChoice: weather)
            let backup = try RestlingBackup(forest: forest, settings: settings, createdAt: date)
            XCTAssertEqual(try RestlingBackup.decode(backup.encoded()), backup)
        }
    }

    func testImportSizeLimitChecksBeforeParsingAndAcceptsItsExactBoundary() throws {
        let backup = try fixture()
        let encoded = try backup.encoded()
        var padded = encoded
        padded.append(Data(repeating: 0x20, count: RestlingBackup.maxDataSize - encoded.count))
        XCTAssertEqual(padded.count, RestlingBackup.maxDataSize)
        XCTAssertEqual(try RestlingBackup.decode(padded), backup)
        padded.append(0x20)
        XCTAssertThrowsError(try RestlingBackup.decode(padded)) { error in
            XCTAssertTrue(error.localizedDescription.contains("20 MB"))
        }
    }

    func testExportUsesTheSameSizeLimitAsImport() throws {
        let profile = ForestProfile(name: "大量记录")
        let events = (0..<110_000).map { _ in
            ForestRestEvent(profileID: profile.id, occurredAt: date, configuredSeconds: 20, outcome: .skipped)
        }
        let forest = try ForestArchive(profiles: [profile], activeProfileID: profile.id,
                                       events: events, recordingStartedAt: date)
        let backup = try RestlingBackup(forest: forest, settings: BackupSettings(), createdAt: date)
        XCTAssertThrowsError(try backup.encoded()) { error in
            XCTAssertTrue(error.localizedDescription.contains("20 MB"))
        }
    }

    func testInvalidCreationTimeOrProgrammaticWeatherCannotBeExported() throws {
        let forest = try fixture().forest
        XCTAssertThrowsError(try RestlingBackup(forest: forest, settings: BackupSettings(),
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)))
        XCTAssertThrowsError(try RestlingBackup(forest: forest,
            settings: BackupSettings(weatherChoice: "not-a-weather"), createdAt: date))
    }

    func testExtremeFiniteDatesAreRejectedBeforeImportedValuesReachTheUI() throws {
        let original = try object()
        for seconds in [1e300, -1e300] {
            var invalidCreation = original
            invalidCreation["createdAt"] = seconds
            try assertRejected(invalidCreation)

            var invalidBaseline = original
            var forest = try XCTUnwrap(original["forest"] as? [String: Any])
            forest["recordingStartedAt"] = seconds
            invalidBaseline["forest"] = forest
            try assertRejected(invalidBaseline)

            var invalidEvent = original
            forest = try XCTUnwrap(original["forest"] as? [String: Any])
            var events = try XCTUnwrap(forest["events"] as? [[String: Any]])
            events[0]["occurredAt"] = seconds
            forest["events"] = events
            invalidEvent["forest"] = forest
            try assertRejected(invalidEvent)

            XCTAssertThrowsError(try RestlingBackup(forest: fixture().forest, settings: BackupSettings(),
                createdAt: Date(timeIntervalSinceReferenceDate: seconds)))
        }
    }
}
