import Foundation
import XCTest
@testable import PomodoroCore

final class ReminderPreferencesTests: XCTestCase {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testDefaultsAndRoundTripKeepIndependentPreferences() throws {
        let defaults = ReminderPreferences()
        XCTAssertFalse(defaults.scheduleEnabled)
        XCTAssertEqual(defaults.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(defaults.startMinute, 540)
        XCTAssertEqual(defaults.endMinute, 1_080)
        XCTAssertTrue(defaults.idlePauseEnabled)
        XCTAssertEqual(defaults.idleThresholdSeconds, 300)
        XCTAssertEqual(defaults.returnGraceSeconds, 30)
        XCTAssertEqual(defaults.prewarningSeconds, 10)
        XCTAssertTrue(defaults.startSoundEnabled)
        XCTAssertTrue(defaults.endSoundEnabled)
        let custom = ReminderPreferences(scheduleEnabled: true, weekdays: [1, 6],
            startMinute: 1_320, endMinute: 360, idlePauseEnabled: false,
            idleThresholdSeconds: 600, returnGraceSeconds: 45, prewarningSeconds: 0,
            startSoundEnabled: false, endSoundEnabled: true)
        XCTAssertEqual(try JSONDecoder().decode(ReminderPreferences.self,
            from: JSONEncoder().encode(custom)), custom)
    }

    func testInvalidValuesNormalizeAndMalformedFieldsRecoverIndependently() throws {
        var settings = ReminderPreferences(weekdays: [-1, 0, 2, 8], startMinute: -1,
            endMinute: Int.max, idleThresholdSeconds: Int.min,
            returnGraceSeconds: Int.max, prewarningSeconds: -3)
        XCTAssertEqual(settings.weekdays, [2])
        XCTAssertEqual(settings.startMinute, 0)
        XCTAssertEqual(settings.endMinute, 1_439)
        XCTAssertEqual(settings.idleThresholdSeconds, 60)
        XCTAssertEqual(settings.returnGraceSeconds, 300)
        XCTAssertEqual(settings.prewarningSeconds, 0)
        settings.weekdays = [0, 1, 7, 8]
        settings.startMinute = Int.max
        settings.endMinute = -20
        settings.idleThresholdSeconds = Int.max
        settings.returnGraceSeconds = -1
        settings.prewarningSeconds = Int.max
        XCTAssertEqual(settings.weekdays, [1, 7])
        XCTAssertEqual(settings.startMinute, 1_439)
        XCTAssertEqual(settings.endMinute, 0)
        XCTAssertEqual(settings.idleThresholdSeconds, 3_600)
        XCTAssertEqual(settings.returnGraceSeconds, 0)
        XCTAssertEqual(settings.prewarningSeconds, 60)
        let json = #"{"scheduleEnabled":true,"weekdays":[0,6,7,9],"startMinute":-30,"endMinute":"bad","idlePauseEnabled":false,"returnGraceSeconds":null,"prewarningSeconds":80,"startSoundEnabled":false}"#
        let decoded = try JSONDecoder().decode(ReminderPreferences.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.scheduleEnabled)
        XCTAssertEqual(decoded.weekdays, [6, 7])
        XCTAssertEqual(decoded.startMinute, 0)
        XCTAssertEqual(decoded.endMinute, 1_080)
        XCTAssertFalse(decoded.idlePauseEnabled)
        XCTAssertEqual(decoded.returnGraceSeconds, 30)
        XCTAssertEqual(decoded.prewarningSeconds, 60)
        XCTAssertFalse(decoded.startSoundEnabled)
        XCTAssertTrue(decoded.endSoundEnabled)
        XCTAssertEqual(try JSONDecoder().decode(ReminderPreferences.self, from: Data("{}".utf8)), ReminderPreferences())
    }

    func testDaytimeWindowRespectsWeekdayAndExactBoundaries() {
        let settings = ReminderPreferences(scheduleEnabled: true)
        for (time, allowed) in [("2026-11-02T08:59:59Z", false),
                                ("2026-11-02T09:00:00Z", true),
                                ("2026-11-02T17:59:59Z", true),
                                ("2026-11-02T18:00:00Z", false),
                                ("2026-11-07T12:00:00Z", false)] {
            XCTAssertEqual(settings.scheduleAllows(at: date(time), calendar: calendar()), allowed, time)
        }
    }

    func testOvernightWindowBelongsToItsStartingWeekday() {
        let settings = ReminderPreferences(scheduleEnabled: true, weekdays: [6],
                                          startMinute: 1_320, endMinute: 360)
        for (time, allowed) in [("2026-11-06T01:00:00Z", false),
                                ("2026-11-06T21:59:59Z", false),
                                ("2026-11-06T22:00:00Z", true),
                                ("2026-11-07T05:59:59Z", true),
                                ("2026-11-07T06:00:00Z", false),
                                ("2026-11-08T01:00:00Z", false)] {
            XCTAssertEqual(settings.scheduleAllows(at: date(time), calendar: calendar()), allowed, time)
        }
        XCTAssertEqual(settings.nextAllowedStart(after: date("2026-11-07T06:00:00Z"), calendar: calendar()),
                       date("2026-11-13T22:00:00Z"))
    }

    func testEqualClockTimesMeanFullSelectedDayAndOpenAtMidnight() {
        let settings = ReminderPreferences(scheduleEnabled: true, weekdays: [4],
                                          startMinute: 540, endMinute: 540)
        XCTAssertTrue(settings.scheduleAllows(at: date("2026-11-04T00:00:00Z"), calendar: calendar()))
        XCTAssertTrue(settings.scheduleAllows(at: date("2026-11-04T23:59:59Z"), calendar: calendar()))
        XCTAssertFalse(settings.scheduleAllows(at: date("2026-11-05T00:00:00Z"), calendar: calendar()))
        XCTAssertEqual(settings.nextAllowedStart(after: date("2026-11-03T23:30:00Z"), calendar: calendar()),
                       date("2026-11-04T00:00:00Z"))
    }

    func testDisabledAndEmptySchedulesHaveClearEligibility() {
        let now = date("2026-11-07T23:00:00Z")
        let disabled = ReminderPreferences(weekdays: [])
        XCTAssertTrue(disabled.scheduleAllows(at: now, calendar: calendar()))
        XCTAssertEqual(disabled.nextAllowedStart(after: now, calendar: calendar()), now)
        let empty = ReminderPreferences(scheduleEnabled: true, weekdays: [])
        XCTAssertFalse(empty.scheduleAllows(at: now, calendar: calendar()))
        XCTAssertNil(empty.nextAllowedStart(after: now, calendar: calendar()))
    }

    func testScheduleUsesSuppliedTimeZoneAndFindsNextWorkingStart() {
        let settings = ReminderPreferences(scheduleEnabled: true)
        let monday = date("2026-11-02T10:00:00Z")
        XCTAssertTrue(settings.scheduleAllows(at: monday, calendar: calendar()))
        XCTAssertFalse(settings.scheduleAllows(at: monday, calendar: calendar("Asia/Shanghai")))
        XCTAssertEqual(settings.nextAllowedStart(after: monday, calendar: calendar()), monday)
        XCTAssertEqual(settings.nextAllowedStart(after: date("2026-11-06T18:00:00Z"), calendar: calendar()),
                       date("2026-11-09T09:00:00Z"))
    }

    func testSpringDSTAdvancesMissingStartOnlyWhenWindowStillExists() {
        let la = calendar("America/Los_Angeles")
        let now = date("2026-03-08T01:50:00-08:00")
        let remainingWindow = ReminderPreferences(scheduleEnabled: true, weekdays: [1],
                                                 startMinute: 150, endMinute: 210)
        XCTAssertEqual(remainingWindow.nextAllowedStart(after: now, calendar: la),
                       date("2026-03-08T03:00:00-07:00"))
        let missingWindow = ReminderPreferences(scheduleEnabled: true, weekdays: [1],
                                               startMinute: 130, endMinute: 160)
        XCTAssertEqual(missingWindow.nextAllowedStart(after: now, calendar: la),
                       date("2026-03-15T02:10:00-07:00"))
    }

    func testFallDSTCanFindTheSecondOccurrenceOfAnOpeningTime() {
        let la = calendar("America/Los_Angeles")
        let settings = ReminderPreferences(scheduleEnabled: true, weekdays: [1],
                                          startMinute: 90, endMinute: 120)
        XCTAssertEqual(settings.nextAllowedStart(after: date("2026-11-01T01:15:00-08:00"), calendar: la),
                       date("2026-11-01T01:30:00-08:00"))
    }
}
