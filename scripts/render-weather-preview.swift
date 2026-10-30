import Foundation

// Render deterministic time samples through the exact app Canvas painter.
// This tool never launches the app or reads/writes a personal forest archive.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/rest-forest-weather-refresh", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: destination, withIntermediateDirectories: true)
let cache = destination.appendingPathComponent("module-cache", isDirectory: true)
try fm.createDirectory(at: cache, withIntermediateDirectories: true)
func execute(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [arguments[0], "-module-cache-path", cache.path] + arguments.dropFirst()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "WeatherPreview", code: Int(process.terminationStatus)) }
}
let coreSources = try fm.contentsOfDirectory(at: project.appendingPathComponent("Sources/PomodoroCore"), includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "swift" }.map(\.path).sorted()
try execute(["swiftc", "-emit-module", "-emit-library", "-module-name", "PomodoroCore"] + coreSources +
            ["-o", destination.appendingPathComponent("libPomodoroCore.dylib").path])
let treeSource = try String(contentsOf: project.appendingPathComponent("Sources/BreaktimeApp/ForestTreeArt.swift"), encoding: .utf8)
let painterSource = treeSource + "\n" + (try String(contentsOf: project.appendingPathComponent("Sources/BreaktimeApp/ForestSceneView.swift"), encoding: .utf8))
let harness = #"""

import AppKit
import ImageIO

private struct WeatherSnapshotView: View {
    let profile: ForestProfile
    let weather: ForestWeather
    let time: TimeInterval
    var body: some View {
        Canvas { context, size in
            var painter = ForestPixelPainter(context: context, size: size, time: time,
                seed: profile.seed, resting: false, climate: ForestAtmosphere(weather: weather))
            painter.paint(profile: profile, groveIndex: 0, progress: 0)
        }.background(Color(red: 0.97, green: 0.96, blue: 0.91))
    }
}

@MainActor
func raster<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: content.frame(width: width, height: height))
    renderer.proposedSize = ProposedViewSize(width: width, height: height)
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("Weather frame render failed") }
    return image
}
func savePNG(_ image: CGImage, at url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fatalError("PNG creation failed") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG finalization failed") }
}
@MainActor
func render() {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let bare = ForestProfile(name: "空地")
    var sprout = bare
    sprout.recordRest(id: UUID(), seconds: 20)
    var mature = bare
    for _ in 0..<24 { mature.recordRest(id: UUID(), seconds: 20) }
    let examples = [("bare", bare), ("sprout", sprout), ("mature", mature)]
    for (name, profile) in examples {
        for weather in ForestWeather.allCases {
            for time in [0.0, 2.0] {
                let image = raster(WeatherSnapshotView(profile: profile, weather: weather, time: time), width: 576, height: 360)
                savePNG(image, at: output.appendingPathComponent("\(name)-\(weather.rawValue)-t\(Int(time)).png"))
            }
        }
    }
    let weatherCases = ForestWeather.allCases
    let comparison = VStack(spacing: 8) {
        ForEach(0..<2) { row in
            HStack(spacing: 8) {
                ForEach(0..<2) { column in
                    let weather = weatherCases[row * 2 + column]
                    VStack(spacing: 0) {
                        WeatherSnapshotView(profile: sprout, weather: weather, time: 2).frame(width: 576, height: 360)
                        Text(weather.title).font(.system(size: 13, weight: .medium)).frame(height: 26)
                    }
                }
            }
        }
    }.padding(12).background(Color(red: 0.97, green: 0.96, blue: 0.91))
    savePNG(raster(comparison, width: 1184, height: 804), at: output.appendingPathComponent("comparison.png"))
    let motionSheet = VStack(spacing: 8) {
        ForEach([ForestWeather.sunny, .breezy, .rainy]) { weather in
            HStack(spacing: 8) {
                ForEach([0, 2], id: \.self) { second in
                    VStack(spacing: 0) {
                        WeatherSnapshotView(profile: sprout, weather: weather, time: Double(second))
                            .frame(width: 576, height: 360)
                        Text("\(weather.title) · \(second) 秒")
                            .font(.system(size: 12)).frame(height: 24)
                    }
                }
            }
        }
    }.padding(12).background(Color(red: 0.97, green: 0.96, blue: 0.91))
    savePNG(raster(motionSheet, width: 1184, height: 1192), at: output.appendingPathComponent("motion-contact-sheet.png"))
    for weather in [ForestWeather.rainy, .breezy, .sunny] {
        let count = 72
        let url = output.appendingPathComponent("sprout-\(weather.rawValue)-motion.gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, count, nil) else { fatalError("GIF creation failed") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<count {
            autoreleasepool {
                let image = raster(WeatherSnapshotView(profile: sprout, weather: weather, time: Double(frame) / 12), width: 576, height: 360)
                CGImageDestinationAddImage(destination, image,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12,
                                                    kCGImagePropertyGIFUnclampedDelayTime: 1.0 / 12]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { fatalError("GIF finalization failed") }
    }
    print("Rendered deterministic 0s/2s samples and 6-second motion clips: \(output.path)")
}
MainActor.assumeIsolated { render() }
"""#
let source = destination.appendingPathComponent("main.swift")
try (painterSource + harness).write(to: source, atomically: true, encoding: .utf8)
let executable = destination.appendingPathComponent("render-weather")
try execute(["swiftc", source.path, "-I", destination.path, "-L", destination.path, "-lPomodoroCore", "-Xlinker", "-rpath", "-Xlinker", destination.path, "-o", executable.path])
let process = Process()
process.executableURL = executable
process.arguments = [destination.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
