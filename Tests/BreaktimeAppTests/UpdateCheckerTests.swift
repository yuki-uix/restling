import Foundation
import XCTest
import PomodoroCore
@testable import BreaktimeApp

final class UpdateCheckerTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (String, UserDefaults) {
        let suite = "UpdateCheckerTests." + UUID().uuidString
        return (suite, try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func configuration(_ source: String = "main") throws -> UpdateConfiguration {
        try XCTUnwrap(UpdateConfiguration(feedURL: URL(string: "https://updates.example.test/\(source).json")!,
                                           homebrewCask: HomebrewCask("publisher/tap/rest-forest")))
    }

    private func feed(_ version: String = "0.8.0", minimumOS: String? = nil) throws -> Data {
        var json: [String: String] = ["version": version,
                                    "releaseNotes": "新增树种与更柔和的天气。",
                                    "releaseURL": "https://example.test/releases/\(version)"]
        json["minimumMacOSVersion"] = minimumOS
        return try JSONSerialization.data(withJSONObject: json)
    }

    @MainActor
    func testUnconfiguredCheckIsHonestAndMakesNoRequest() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let loader = CountingUpdateLoader(data: try feed())
        let checker = UpdateChecker(configuration: nil, currentVersion: "0.7.0", defaults: defaults,
                                    loader: { try await loader.load($0) })
        await checker.checkForUpdates(manually: true)
        XCTAssertEqual(checker.state, .notConfigured)
        XCTAssertNil(checker.lastCheckedAt)
        XCTAssertNil(checker.availableRelease)
        XCTAssertFalse(checker.shouldShowBanner)
        let calls = await loader.calls
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testDailyAutomaticThrottlePersistsAcrossLaunchesButManualCheckBypassesIt() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let loader = CountingUpdateLoader(data: try feed())
        let config = try configuration()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let checker = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                    now: { start }, loader: { try await loader.load($0) })
        await checker.checkForUpdates()
        await checker.checkForUpdates()
        XCTAssertEqual(checker.lastCheckedAt, start)
        XCTAssertTrue(checker.shouldShowBanner)

        let restored = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                     now: { start.addingTimeInterval(3_600) }, loader: { try await loader.load($0) })
        XCTAssertEqual(restored.availableRelease?.version, AppVersion("0.8.0"))
        await restored.checkForUpdates()
        var calls = await loader.calls
        XCTAssertEqual(calls, 1)
        await restored.checkForUpdates(manually: true)
        calls = await loader.calls
        XCTAssertEqual(calls, 2)

        let tomorrow = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                     now: { start.addingTimeInterval(90_001) }, loader: { try await loader.load($0) })
        await tomorrow.checkForUpdates()
        calls = await loader.calls
        XCTAssertEqual(calls, 3)
    }

    @MainActor
    func testOfflineFailureDoesNotEraseCachedReleaseAndDismissalWaitsForNewerVersion() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = try configuration()
        let data = try feed()
        let checker = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                    loader: { _ in data })
        await checker.checkForUpdates(manually: true)
        checker.dismissAvailableVersion()
        XCTAssertFalse(checker.shouldShowBanner)

        let offline = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                    loader: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertFalse(offline.shouldShowBanner)
        await offline.checkForUpdates(manually: true)
        XCTAssertEqual(offline.availableRelease?.version, AppVersion("0.8.0"))
        XCTAssertNotNil(offline.lastError)
        guard case .available = offline.state else { return XCTFail("Cached release was lost") }
        XCTAssertFalse(offline.shouldShowBanner)

        let nextData = try feed("0.9.0")
        let newer = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                  loader: { _ in nextData })
        await newer.checkForUpdates(manually: true)
        XCTAssertTrue(newer.shouldShowBanner)
        XCTAssertEqual(newer.availableRelease?.version, AppVersion("0.9.0"))
    }

    @MainActor
    func testUnavailableFeedNeverClaimsTheAppIsUpToDateAndFailuresAreThrottled() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let loader = CountingUpdateLoader(data: nil)
        let checker = UpdateChecker(configuration: try configuration(), currentVersion: "0.7.0", defaults: defaults,
                                    loader: { try await loader.load($0) })
        await checker.checkForUpdates()
        await checker.checkForUpdates()
        guard case .failed = checker.state else { return XCTFail("Offline check must not report success") }
        XCTAssertNil(checker.lastCheckedAt)
        let calls = await loader.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testAutomaticPreferencePersistsAndDoesNotDisableManualChecking() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = try configuration()
        let loader = CountingUpdateLoader(data: try feed())
        let checker = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                    loader: { try await loader.load($0) })
        checker.automaticChecksEnabled = false
        let restored = UpdateChecker(configuration: config, currentVersion: "0.7.0", defaults: defaults,
                                     loader: { try await loader.load($0) })
        XCTAssertFalse(restored.automaticChecksEnabled)
        await restored.checkForUpdates()
        var calls = await loader.calls
        XCTAssertEqual(calls, 0)
        await restored.checkForUpdates(manually: true)
        calls = await loader.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testInFlightManualRequestsAreDeduplicated() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let loader = BlockingUpdateLoader()
        let checker = UpdateChecker(configuration: try configuration(), currentVersion: "0.7.0", defaults: defaults,
                                    loader: { try await loader.load($0) })
        let first = Task { await checker.checkForUpdates(manually: true) }
        await loader.waitUntilStarted()
        XCTAssertEqual(checker.state, .checking)
        await checker.checkForUpdates(manually: true)
        let calls = await loader.calls
        XCTAssertEqual(calls, 1)
        await loader.finish(with: try feed())
        await first.value
        XCTAssertTrue(checker.shouldShowBanner)
    }

    @MainActor
    func testChangingFeedDoesNotReuseAnotherPublishersCacheOrThrottle() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let loader = CountingUpdateLoader(data: try feed())
        let checker = UpdateChecker(configuration: try configuration("first"), currentVersion: "0.7.0", defaults: defaults,
                                    loader: { try await loader.load($0) })
        await checker.checkForUpdates()
        checker.dismissAvailableVersion()
        let other = UpdateChecker(configuration: try configuration("other"), currentVersion: "0.7.0", defaults: defaults,
                                  loader: { try await loader.load($0) })
        XCTAssertEqual(other.state, .idle)
        XCTAssertNil(other.availableRelease)
        XCTAssertNil(other.lastCheckedAt)
        XCTAssertNil(other.dismissedVersion)
        await other.checkForUpdates()
        XCTAssertTrue(other.shouldShowBanner)
        let calls = await loader.calls
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testNewerReleaseRequiringAnotherMacOSIsVisibleButDoesNotShowUpgradeBanner() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = try feed(minimumOS: "15.0.0")
        let checker = UpdateChecker(configuration: try configuration(), currentVersion: "0.7.0",
                                    currentMacOSVersion: AppVersion("14.0.0"), defaults: defaults,
                                    loader: { _ in data })
        await checker.checkForUpdates(manually: true)
        guard case .unsupported(let release) = checker.state else { return XCTFail("Expected unsupported update") }
        XCTAssertEqual(release.version, AppVersion("0.8.0"))
        XCTAssertNotNil(checker.availableRelease)
        XCTAssertFalse(checker.shouldShowBanner)
    }

    @MainActor
    func testInstalledNewerVersionIsNotOfferedADowngrade() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = try feed("0.7.0")
        let checker = UpdateChecker(configuration: try configuration(), currentVersion: "0.8.0", defaults: defaults,
                                    loader: { _ in data })
        await checker.checkForUpdates(manually: true)
        XCTAssertEqual(checker.state, .upToDate)
        XCTAssertNil(checker.availableRelease)
        XCTAssertFalse(checker.shouldShowBanner)
    }

    @MainActor
    func testInvalidAndOversizedFeedsReportFailureWithoutInventingARelease() async throws {
        for data in [Data("not JSON".utf8), Data(repeating: 65, count: 131_073)] {
            let (suite, defaults) = try fixture()
            defer { defaults.removePersistentDomain(forName: suite) }
            let checker = UpdateChecker(configuration: try configuration(), currentVersion: "0.7.0", defaults: defaults,
                                        loader: { _ in data })
            await checker.checkForUpdates(manually: true)
            guard case .failed = checker.state else { return XCTFail("Expected malformed feed failure") }
            XCTAssertNil(checker.availableRelease)
            XCTAssertNil(checker.lastCheckedAt)
        }
    }

    @MainActor
    func testCancellationDoesNotThrottleTheNextAttempt() async throws {
        let (suite, defaults) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = try feed()
        let cancelled = UpdateChecker(configuration: try configuration(), currentVersion: "0.7.0", defaults: defaults,
                                      loader: { _ in throw CancellationError() })
        await cancelled.checkForUpdates()
        XCTAssertEqual(cancelled.state, .idle)
        XCTAssertNil(cancelled.lastError)
        let next = UpdateChecker(configuration: try configuration(), currentVersion: "0.7.0", defaults: defaults,
                                 loader: { _ in data })
        await next.checkForUpdates()
        XCTAssertTrue(next.shouldShowBanner)
    }

    func testConfigurationRejectsHTTPAndEmbeddedCredentials() throws {
        for raw in ["http://example.test/feed.json", "file:///tmp/feed.json", "https://user:secret@example.test/feed.json"] {
            XCTAssertNil(UpdateConfiguration(feedURL: URL(string: raw)!))
        }
        XCTAssertNotNil(try configuration())
    }
}

private actor CountingUpdateLoader {
    private let data: Data?
    private(set) var calls = 0
    init(data: Data?) { self.data = data }
    func load(_ url: URL) throws -> Data {
        calls += 1
        guard let data else { throw URLError(.notConnectedToInternet) }
        return data
    }
}

private actor BlockingUpdateLoader {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Data, Error>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func load(_ url: URL) async throws -> Data {
        calls += 1
        for waiter in startedWaiters { waiter.resume() }
        startedWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func finish(with data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}
