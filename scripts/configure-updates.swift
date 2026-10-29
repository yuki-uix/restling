import Foundation

// This is a build-time tool for the staging bundle, not an app preference UI.
// Configuration is written before signing; absent values leave updates unbound.
func fail(_ message: String) -> Never {
    fputs("Update configuration: \(message)\n", stderr)
    exit(1)
}

func httpsURL(_ raw: String) -> URL? {
    guard raw.utf8.count <= 2_048,
          raw.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
          let components = URLComponents(string: raw),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty,
          components.user == nil, components.password == nil else { return nil }
    return components.url
}

func validCask(_ raw: String) -> Bool {
    guard raw.utf8.count <= 256 else { return false }
    let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count == 3 && parts.allSatisfy { part in
        func alphanumeric(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard let first = part.utf8.first, alphanumeric(first) else { return false }
        return part.utf8.allSatisfy { alphanumeric($0) || $0 == 46 || $0 == 95 || $0 == 43 || $0 == 45 }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print("Usage: swift configure-updates.swift /path/to/staged/Info.plist")
    print("Environment: FOREST_UPDATE_FEED_URL (HTTPS), FOREST_HOMEBREW_CASK (owner/tap/cask, optional)")
    print("Leave both unset to build without a public update source.")
    exit(0)
}
guard arguments.count == 1 else { fail("expected the staging Info.plist path; use --help for usage.") }
let environment = ProcessInfo.processInfo.environment
let rawFeed = environment["FOREST_UPDATE_FEED_URL"].flatMap { $0.isEmpty ? nil : $0 }
let cask = environment["FOREST_HOMEBREW_CASK"].flatMap { $0.isEmpty ? nil : $0 }
if let rawFeed, httpsURL(rawFeed) == nil {
    fail("FOREST_UPDATE_FEED_URL must be a valid HTTPS URL without credentials or whitespace.")
}
if let cask, !validCask(cask) {
    fail("FOREST_HOMEBREW_CASK must be a three-part owner/tap/cask identifier containing only letters, digits, '.', '_', '+', '-'.")
}
if cask != nil && rawFeed == nil {
    fail("FOREST_HOMEBREW_CASK also requires FOREST_UPDATE_FEED_URL.")
}

do {
    let url = URL(fileURLWithPath: arguments[0])
    var format = PropertyListSerialization.PropertyListFormat.xml
    let source = try Data(contentsOf: url)
    guard var values = try PropertyListSerialization.propertyList(from: source, options: [], format: &format) as? [String: Any] else {
        fail("Info.plist must contain a dictionary.")
    }
    values.removeValue(forKey: "ForestUpdateFeedURL")
    values.removeValue(forKey: "ForestHomebrewCask")
    if let rawFeed { values["ForestUpdateFeedURL"] = httpsURL(rawFeed)!.absoluteString }
    if let cask { values["ForestHomebrewCask"] = cask }
    let result = try PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0)
    try result.write(to: url, options: .atomic)
    print(rawFeed == nil ? "Update source: not configured" : "Update source configured for the staging bundle")
} catch {
    fail(error.localizedDescription)
}
