import Foundation

func fail(_ message: String) -> Never {
    fputs("Update feed: \(message)\n", stderr)
    exit(1)
}

let usage = """
Usage: swift make-update-feed.swift --version VERSION --release-url HTTPS_URL \\
       --notes-file PATH --output PATH [--minimum-macos VERSION]

Creates the public JSON metadata consumed by the app's update checker.
VERSION accepts 1-3 numeric components, optional v prefix and SemVer suffixes.
The default minimum macOS version is 13.0.0. No upload is performed.
"""

func normalizedVersion(_ raw: String) -> String? {
    guard !raw.isEmpty, raw.utf8.count <= 100 else { return nil }
    let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    let build = value.split(separator: "+", omittingEmptySubsequences: false)
    guard build.count <= 2 else { return nil }
    let parts = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    func numeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    func validNumber(_ value: String) -> Bool {
        numeric(value) && (value.count == 1 || !value.hasPrefix("0"))
    }
    func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }
    var core = parts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard (1...3).contains(core.count), core.allSatisfy(validNumber) else { return nil }
    while core.count < 3 { core.append("0") }
    let prerelease = parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
    let metadata = build.count == 2 ? build[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
    guard prerelease.allSatisfy({ identifier($0) && (!numeric($0) || validNumber($0)) }),
          metadata.allSatisfy(identifier) else { return nil }
    let normalized = core.joined(separator: ".")
        + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
        + (metadata.isEmpty ? "" : "+" + metadata.joined(separator: "."))
    return normalized.utf8.count <= 100 ? normalized : nil
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

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}
let allowed = Set(["--version", "--release-url", "--notes-file", "--minimum-macos", "--output"])
var options: [String: String] = [:]
var index = 0
while index < arguments.count {
    let name = arguments[index]
    guard allowed.contains(name) else { fail("unknown option '\(name)'; use --help for usage.") }
    guard options[name] == nil else { fail("option '\(name)' was provided more than once.") }
    guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { fail("missing value for '\(name)'.") }
    options[name] = arguments[index + 1]
    index += 2
}
for key in ["--version", "--release-url", "--notes-file", "--output"] where options[key] == nil {
    fail("missing \(key); use --help for usage.")
}
guard let version = normalizedVersion(options["--version"]!) else { fail("--version is not a valid release version.") }
guard let releaseURL = httpsURL(options["--release-url"]!) else { fail("--release-url must use HTTPS, without credentials or whitespace.") }
guard let minimum = normalizedVersion(options["--minimum-macos"] ?? "13.0.0") else { fail("--minimum-macos is not a valid version.") }

do {
    let notesURL = URL(fileURLWithPath: options["--notes-file"]!).standardizedFileURL
    let outputURL = URL(fileURLWithPath: options["--output"]!).standardizedFileURL
    guard notesURL != outputURL else { fail("--output must not overwrite the release notes file.") }
    let attributes = try notesURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard attributes.isRegularFile == true, (attributes.fileSize ?? Int.max) <= 128 * 1_024 else {
        fail("--notes-file must be a regular UTF-8 text file no larger than 128 KiB.")
    }
    let notes = try String(contentsOf: notesURL, encoding: .utf8)
    guard notes.count <= 20_000 else { fail("release notes must not exceed 20,000 characters.") }
    let payload = ["version": version, "releaseURL": releaseURL.absoluteString,
                   "releaseNotes": notes, "minimumMacOSVersion": minimum]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    guard data.count <= 128 * 1_024 else { fail("encoded update feed exceeds 128 KiB.") }
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: outputURL, options: .atomic)
    print("Generated update metadata for \(version): \(outputURL.path)")
} catch {
    fail(error.localizedDescription)
}
