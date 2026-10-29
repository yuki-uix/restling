import Foundation
import XCTest
@testable import PomodoroCore

final class AppReleaseTests: XCTestCase {
    func testNumericReleaseComparisonAndNormalization() throws {
        XCTAssertLessThan(try version("0.9.9"), try version("0.10.0"))
        XCTAssertLessThan(try version("1.99.9"), try version("2.0.0"))
        XCTAssertEqual(try version("v13.0").description, "13.0.0")
        XCTAssertEqual(try version("13"), try version("13.0.0"))
        XCTAssertEqual(try version("26.6.2").description, "26.6.2")
        XCTAssertLessThan(try version("999999999999999999999.0.0"), try version("1000000000000000000000.0.0"))
    }

    func testSemverPrereleasePriorityAndBuildMetadata() throws {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                       "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(try version(pair.0), try version(pair.1))
        }
        XCTAssertEqual(try version("1.0.0+build.12"), try version("1.0.0+build.13"))
        XCTAssertEqual(try version("v1.0.0-beta.2+build.13").description, "1.0.0-beta.2+build.13")
    }

    func testMalformedVersionsCannotCreateUpdatePrompts() {
        for raw in ["", "v", "1.2.3.4", "01.0.0", "1.02.3", "1.2.-3", "1.0.0-01", "1.0.0-",
                    "1.0.0-alpha..1", "1.0.0+", "1.0.0+a+b", " 1.0.0", "1.0.0\n", "１.0.0",
                    "1.0.0-💚", String(repeating: "1", count: 101)] {
            XCTAssertNil(AppVersion(raw), raw)
        }
    }

    func testReleaseFeedDecodesVersionNotesAndMinimumOS() throws {
        let data = try payload(version: "v0.8.0", notes: "新增林间天气\n改善细雨。", minimum: "13.0")
        let release = try AppRelease(data: data)
        XCTAssertEqual(release.version, try version("0.8.0"))
        XCTAssertEqual(release.releaseNotes, "新增林间天气\n改善细雨。")
        XCTAssertEqual(release.minimumMacOSVersion, try version("13.0.0"))
        XCTAssertEqual(release.releaseURL.absoluteString, "https://github.com/example/rest-forest/releases/tag/v0.8.0")
        XCTAssertEqual(try JSONDecoder().decode(AppRelease.self, from: data), release)
    }

    func testMissingOptionalFieldsDoNotMakeAValidReleaseFail() throws {
        let data = Data("{\"version\":\"0.8.0\",\"releaseURL\":\"https://example.com/releases/0.8.0\"}".utf8)
        let release = try AppRelease(data: data)
        XCTAssertEqual(release.releaseNotes, "")
        XCTAssertNil(release.minimumMacOSVersion)
    }

    func testReleaseLinksCannotContainCredentialsOrUnsafeSchemes() throws {
        for url in ["http://example.com/release", "file:///tmp/release", "javascript:alert(1)",
                    "https:///release", "https://user:password@example.com/release", "https://@example.com/release",
                    "https://example.com/release\n", "https://example.com/a b"] {
            XCTAssertThrowsError(try AppRelease(data: payload(url: url)), url)
        }
        XCTAssertNoThrow(try AppRelease(data: payload(url: "https://example.com/release#notes")))
    }

    func testInvalidOrExcessiveFeedDataIsRejected() throws {
        XCTAssertThrowsError(try AppRelease(data: payload(version: "newest")))
        XCTAssertThrowsError(try AppRelease(data: payload(minimum: "invalid")))
        XCTAssertThrowsError(try AppRelease(data: payload(notes: String(repeating: "a", count: 20_001))))
        XCTAssertThrowsError(try AppRelease(data: Data(repeating: 32, count: 128 * 1_024 + 1)))
        XCTAssertThrowsError(try AppRelease(data: Data("not JSON".utf8)))
    }

    func testHomebrewCommandOnlyAcceptsFullyQualifiedCaskTokens() throws {
        let cask = try XCTUnwrap(HomebrewCask("owner/tap/rest-forest"))
        XCTAssertEqual(cask.token, "owner/tap/rest-forest")
        XCTAssertEqual(cask.upgradeCommand, "brew upgrade --cask owner/tap/rest-forest")
        for raw in ["rest-forest", "owner/rest-forest", "owner/tap/rest-forest/extra", "owner//rest-forest",
                    "owner/tap/--help", "owner/tap/app;rm", "owner/tap/app$(whoami)", "owner/tap/`id`",
                    "owner/tap/app name", "owner/tap/app\n", "owner/tap/../app", "用户/tap/app"] {
            XCTAssertNil(HomebrewCask(raw), raw)
        }
    }

    private func version(_ raw: String) throws -> AppVersion {
        try XCTUnwrap(AppVersion(raw))
    }

    private func payload(version: String = "0.8.0", notes: String = "新的休息体验。",
                         url: String = "https://github.com/example/rest-forest/releases/tag/v0.8.0",
                         minimum: String? = nil) throws -> Data {
        var value = ["version": version, "releaseNotes": notes, "releaseURL": url]
        if let minimum { value["minimumMacOSVersion"] = minimum }
        return try JSONSerialization.data(withJSONObject: value)
    }
}
