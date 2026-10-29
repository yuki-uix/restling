import Foundation
import Combine
import PomodoroCore

struct UpdateConfiguration: Equatable, Sendable {
    let feedURL: URL
    let homebrewCask: HomebrewCask?

    init?(feedURL: URL, homebrewCask: HomebrewCask? = nil) {
        guard Self.isAllowedURL(feedURL) else { return nil }
        self.feedURL = feedURL
        self.homebrewCask = homebrewCask
    }

    static func fromBundle(_ bundle: Bundle = .main) -> UpdateConfiguration? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "ForestUpdateFeedURL") as? String,
              let url = URL(string: rawURL), isAllowedURL(url) else { return nil }
        let cask = (bundle.object(forInfoDictionaryKey: "ForestHomebrewCask") as? String)
            .flatMap(HomebrewCask.init)
        return UpdateConfiguration(feedURL: url, homebrewCask: cask)
    }

    fileprivate static func isAllowedURL(_ url: URL) -> Bool {
        let raw = url.absoluteString
        return url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty &&
            url.user == nil && url.password == nil && raw.utf8.count <= 2_048 &&
            raw.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }
}

enum UpdateCheckState: Equatable {
    case notConfigured
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case failed(String)
    case unsupported(AppRelease)
}

typealias UpdateFeedLoader = @Sendable (URL) async throws -> Data

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateCheckState
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var dismissedVersion: String?
    @Published private(set) var lastError: String?
    @Published var automaticChecksEnabled: Bool {
        didSet { defaults.set(automaticChecksEnabled, forKey: storageKey + ".automaticChecksEnabled") }
    }

    let currentVersion: AppVersion
    let currentMacOSVersion: AppVersion
    let configuration: UpdateConfiguration?

    private let defaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let loader: UpdateFeedLoader
    private var cachedRelease: AppRelease?
    private var cachedData: Data?
    private var lastAttemptAt: Date?
    private var isChecking = false

    private struct Archive: Codable {
        let feedURL: String
        let lastAttemptAt: Date?
        let lastCheckedAt: Date?
        let dismissedVersion: String?
        let releaseData: Data?
    }

    init(configuration: UpdateConfiguration? = UpdateConfiguration.fromBundle(),
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         currentMacOSVersion: AppVersion? = nil,
         defaults: UserDefaults = .standard,
         storageKey: String = "appUpdates.v1",
         now: @escaping () -> Date = Date.init,
         loader: @escaping UpdateFeedLoader = { url in try await UpdateChecker.loadFeed(url) }) {
        self.configuration = configuration
        self.currentVersion = AppVersion(currentVersion) ?? AppVersion("0.0.0")!
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.currentMacOSVersion = currentMacOSVersion ?? AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")!
        self.defaults = defaults
        self.storageKey = storageKey
        self.now = now
        self.loader = loader
        automaticChecksEnabled = defaults.object(forKey: storageKey + ".automaticChecksEnabled") as? Bool ?? true
        state = configuration == nil ? .notConfigured : .idle

        // Cache, dismissal and throttling belong to one feed. Changing the
        // publisher must not display another source's cached release or skip it.
        if let configuration,
           let data = defaults.data(forKey: storageKey),
           let archive = try? JSONDecoder().decode(Archive.self, from: data),
           archive.feedURL == configuration.feedURL.absoluteString {
            lastAttemptAt = Self.validDate(archive.lastAttemptAt)
            lastCheckedAt = Self.validDate(archive.lastCheckedAt)
            dismissedVersion = archive.dismissedVersion.flatMap { AppVersion($0)?.description }
            if let feedData = archive.releaseData,
               let release = try? AppRelease(data: feedData) {
                cachedData = feedData
                cachedRelease = release
                state = settledState(for: release)
            }
        }
    }

    var availableRelease: AppRelease? {
        guard let cachedRelease, cachedRelease.version > currentVersion else { return nil }
        return cachedRelease
    }

    var shouldShowBanner: Bool {
        guard let release = availableRelease,
              release.minimumMacOSVersion.map({ $0 <= currentMacOSVersion }) ?? true else { return false }
        if let dismissedVersion, let dismissed = AppVersion(dismissedVersion) {
            return release.version > dismissed
        }
        return true
    }

    func dismissAvailableVersion() {
        guard let release = availableRelease else { return }
        dismissedVersion = release.version.description
        save()
    }

    func checkForUpdates(manually: Bool = false) async {
        guard let configuration else {
            state = .notConfigured
            return
        }
        guard !isChecking else { return }
        if !manually {
            guard automaticChecksEnabled else { return }
            if let lastAttemptAt {
                let elapsed = currentDate().timeIntervalSince(lastAttemptAt)
                if elapsed >= 0 && elapsed < 24 * 60 * 60 { return }
            }
        }

        let previousState = state
        let previousAttempt = lastAttemptAt
        isChecking = true
        state = .checking
        lastError = nil
        lastAttemptAt = currentDate()
        save()
        defer { isChecking = false }

        do {
            try Task.checkCancellation()
            let data = try await loader(configuration.feedURL)
            try Task.checkCancellation()
            guard data.count <= 131_072 else { throw UpdateFeedError.payloadTooLarge }
            let release = try AppRelease(data: data)
            cachedData = data
            cachedRelease = release
            lastCheckedAt = currentDate()
            state = settledState(for: release)
            save()
        } catch is CancellationError {
            lastAttemptAt = previousAttempt
            state = previousState
            save()
        } catch let error as URLError where error.code == .cancelled {
            lastAttemptAt = previousAttempt
            state = previousState
            save()
        } catch {
            let message = Self.failureMessage(error)
            lastError = message
            // An offline check must not erase an update already learned about.
            state = cachedRelease.map(settledState(for:)) ?? .failed(message)
            save()
        }
    }

    private func settledState(for release: AppRelease) -> UpdateCheckState {
        guard release.version > currentVersion else { return .upToDate }
        if let minimum = release.minimumMacOSVersion, minimum > currentMacOSVersion {
            return .unsupported(release)
        }
        return .available(release)
    }

    private func save() {
        guard let configuration else { return }
        let archive = Archive(feedURL: configuration.feedURL.absoluteString,
                              lastAttemptAt: lastAttemptAt, lastCheckedAt: lastCheckedAt,
                              dismissedVersion: dismissedVersion, releaseData: cachedData)
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: storageKey) }
    }

    private func currentDate() -> Date { Self.validDate(now()) ?? Date() }
    private static func validDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return date
    }

    private static func failureMessage(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "暂时无法连接网络，请稍后再检查。"
            case .timedOut:
                return "检查更新超时，请稍后重试。"
            default: return "暂时无法获取更新信息，请稍后重试。"
            }
        }
        if error is DecodingError || error is AppReleaseError {
            return "更新源的信息格式不正确，请稍后再检查。"
        }
        switch error as? UpdateFeedError {
        case .payloadTooLarge: return "更新信息过大，暂时无法读取。"
        case .invalidResponse: return "更新源暂时不可用，请稍后再检查。"
        case .none: return "暂时无法获取更新信息，请稍后重试。"
        }
    }

    nonisolated static func loadFeed(_ url: URL) async throws -> Data {
        guard UpdateConfiguration.isAllowedURL(url) else { throw UpdateFeedError.invalidResponse }
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 10
        settings.timeoutIntervalForResource = 10
        settings.waitsForConnectivity = false
        let session = URLSession(configuration: settings, delegate: UpdateRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let responseURL = response.url, UpdateConfiguration.isAllowedURL(responseURL) else {
            throw UpdateFeedError.invalidResponse
        }
        guard response.expectedContentLength <= 131_072 else { throw UpdateFeedError.payloadTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 131_072 else { throw UpdateFeedError.payloadTooLarge }
            data.append(byte)
        }
        return data
    }
}

private enum UpdateFeedError: Error {
    case invalidResponse
    case payloadTooLarge
}

private final class UpdateRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url.map(UpdateConfiguration.isAllowedURL) ?? false
        completionHandler(allowed ? request : nil)
    }
}
