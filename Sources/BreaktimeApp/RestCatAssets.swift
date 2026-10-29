import Foundation

enum RestCatAssets {
    static var windowDirectory: URL? {
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("CatWindowCute", isDirectory: true),
           FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) {
            return folder
        }
        // SwiftPM supplies a separate resource bundle for development. Production
        // app bundles carry the files directly and should fail gracefully if missing.
        if Bundle.main.bundleIdentifier != "local.yuki.breaktime" {
            return Bundle.module.url(forResource: "CatWindowCute", withExtension: nil, subdirectory: "Resources")
        }
        return nil
    }
}
