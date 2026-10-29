import Foundation

/// A release version whose precedence follows SemVer. Missing minor/patch
/// components are normalized to zero so macOS versions such as 13.0 also work.
/// Numeric components are compared as strings, avoiding integer overflow.
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    private let core: [String]
    private let prerelease: [String]
    private let build: [String]

    public init?(_ raw: String) {
        guard !raw.isEmpty, raw.utf8.count <= 100 else { return nil }
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        let versionParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        var numbers = versionParts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(numbers.count), numbers.allSatisfy(Self.validNumericIdentifier) else { return nil }
        while numbers.count < 3 { numbers.append("0") }
        let preview = versionParts.count == 2
            ? String(versionParts[1]).split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard preview.allSatisfy({ Self.validIdentifier($0) && (!Self.isNumeric($0) || Self.validNumericIdentifier($0)) }) else { return nil }
        let metadata = buildParts.count == 2
            ? String(buildParts[1]).split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard metadata.allSatisfy(Self.validIdentifier) else { return nil }
        core = numbers
        prerelease = preview
        build = metadata
    }

    public var description: String {
        core.joined(separator: ".")
            + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
            + (build.isEmpty ? "" : "+" + build.joined(separator: "."))
    }

    /// Build metadata does not mean a newer release, so it is ignored for both
    /// equality and ordering. This keeps Comparable's equality consistent.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.core == rhs.core && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (left, right) in zip(lhs.core, rhs.core) where left != right {
            return Self.numericLess(left, right)
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = Self.isNumeric(left), rightNumeric = Self.isNumeric(right)
            if leftNumeric && rightNumeric { return Self.numericLess(left, right) }
            if leftNumeric != rightNumeric { return leftNumeric }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func numericLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validNumericIdentifier(_ value: String) -> Bool {
        isNumeric(value) && (value.count == 1 || !value.hasPrefix("0"))
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }
}

public enum AppReleaseError: Error, LocalizedError {
    case payloadTooLarge
    case invalidVersion
    case invalidMinimumMacOSVersion
    case invalidReleaseURL
    case notesTooLong

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: return "更新信息超过允许的大小。"
        case .invalidVersion: return "更新信息中的版本号无效。"
        case .invalidMinimumMacOSVersion: return "更新信息中的系统版本要求无效。"
        case .invalidReleaseURL: return "更新说明地址需要有效的 HTTPS 链接。"
        case .notesTooLong: return "更新说明超过允许的长度。"
        }
    }
}

/// Public update metadata. It never supplies executable commands or downloads
/// an application; the client constructs its own validated Homebrew command.
public struct AppRelease: Decodable, Equatable, Sendable {
    public let version: AppVersion
    public let releaseNotes: String
    public let releaseURL: URL
    public let minimumMacOSVersion: AppVersion?

    private enum CodingKeys: String, CodingKey {
        case version, releaseNotes, releaseURL, minimumMacOSVersion
    }

    public init(data: Data) throws {
        guard data.count <= 128 * 1_024 else { throw AppReleaseError.payloadTooLarge }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawVersion = try values.decode(String.self, forKey: .version)
        guard let version = AppVersion(rawVersion) else { throw AppReleaseError.invalidVersion }
        let notes = try values.decodeIfPresent(String.self, forKey: .releaseNotes) ?? ""
        guard notes.count <= 20_000 else { throw AppReleaseError.notesTooLong }
        let rawURL = try values.decode(String.self, forKey: .releaseURL)
        guard rawURL.utf8.count <= 2_048,
              rawURL.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { throw AppReleaseError.invalidReleaseURL }
        let minimum: AppVersion?
        if let rawMinimum = try values.decodeIfPresent(String.self, forKey: .minimumMacOSVersion) {
            guard let parsed = AppVersion(rawMinimum) else { throw AppReleaseError.invalidMinimumMacOSVersion }
            minimum = parsed
        } else { minimum = nil }
        self.version = version
        releaseNotes = notes
        releaseURL = url
        minimumMacOSVersion = minimum
    }
}

/// A fully qualified Cask identifier, never arbitrary text received from a feed.
public struct HomebrewCask: Equatable, Sendable {
    public let token: String

    public init?(_ raw: String) {
        guard raw.utf8.count <= 256 else { return nil }
        let components = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3, components.allSatisfy({ value in
            guard let first = value.utf8.first,
                  (48...57).contains(first) || (65...90).contains(first) || (97...122).contains(first) else { return false }
            return value.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || $0 == 46 || $0 == 95 || $0 == 43 || $0 == 45
            }
        }) else { return nil }
        token = raw
    }

    public var upgradeCommand: String { "brew upgrade --cask \(token)" }
}
