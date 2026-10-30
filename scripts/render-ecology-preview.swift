import Foundation
import ImageIO

// Deterministic render-only fixtures use the real Canvas painters. No app is
// launched, and no personal profile, event archive or preferences are accessed.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ??
    project.appendingPathComponent("output/epic19-visual").path, isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: destination, withIntermediateDirectories: true)
let cache = destination.appendingPathComponent("module-cache", isDirectory: true)
try fm.createDirectory(at: cache, withIntermediateDirectories: true)

func execute(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "EcologyPreview", code: Int(process.terminationStatus))
    }
}
let core = try fm.contentsOfDirectory(at: project.appendingPathComponent("Sources/PomodoroCore"),
                                    includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "swift" }.map(\.path).sorted()
try execute(["swiftc", "-module-cache-path", cache.path, "-emit-module", "-emit-library", "-module-name", "PomodoroCore"] + core +
            ["-o", destination.appendingPathComponent("libPomodoroCore.dylib").path])
let art = try String(contentsOf: project.appendingPathComponent("Sources/BreaktimeApp/ForestTreeArt.swift"), encoding: .utf8)
let scene = try String(contentsOf: project.appendingPathComponent("Sources/BreaktimeApp/ForestSceneView.swift"), encoding: .utf8)
let catalogue = try String(contentsOf: project.appendingPathComponent("Sources/BreaktimeApp/ForestCatalogueView.swift"), encoding: .utf8)
guard let marker = catalogue.range(of: "private struct CatalogueTreeIllustration") else {
    throw NSError(domain: "EcologyPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Catalogue painter marker missing"])
}
let catalogueArt = String(catalogue[marker.lowerBound...])
let harness = #"""
import AppKit
import ImageIO

private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)
private struct EcologySnapshot: View {
    let profile: ForestProfile
    let grove: Int
    let weather: ForestWeather
    var time: TimeInterval = 0
    var resting = false
    var reduceMotion = false
    var body: some View {
        Canvas { context, size in
            var painter = ForestPixelPainter(context: context, size: size, time: reduceMotion ? 0 : time,
                seed: profile.seed &+ UInt64(grove) &* 0x9E3779B97F4A7C15,
                resting: resting, climate: ForestAtmosphere(weather: weather))
            painter.paint(profile: profile, groveIndex: grove, progress: 0)
        }.background(paper)
    }
}

@MainActor
private func raster<Content: View>(_ content: Content, width: Int, height: Int) -> CGImage {
    let renderer = ImageRenderer(content: content.frame(width: CGFloat(width), height: CGFloat(height)))
    renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("Canvas render failed") }
    return image
}

private func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
        fatalError("PNG destination failed")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    return data as Data
}

@MainActor
private func sheet(_ tiles: [(String, CGImage)], columns: Int, width: Int, height: Int, to url: URL) {
    let rows = (tiles.count + columns - 1) / columns
    let canvasWidth = columns * width, canvasHeight = rows * height
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasWidth, pixelsHigh: canvasHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: canvasWidth * 4, bitsPerPixel: 32), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Contact sheet allocation failed")
    }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
    NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))).fill()
    for (index, tile) in tiles.enumerated() {
        let x = (index % columns) * width
        let y = canvasHeight - (index / columns + 1) * height
        let imageWidth = CGFloat(tile.1.width), imageHeight = CGFloat(tile.1.height)
        let scale = min(CGFloat(width - 8) / imageWidth, CGFloat(height - 30) / imageHeight)
        let fitWidth = imageWidth * scale, fitHeight = imageHeight * scale
        let image = NSImage(cgImage: tile.1, size: NSSize(width: imageWidth, height: imageHeight))
        image.draw(in: NSRect(x: CGFloat(x) + (CGFloat(width) - fitWidth) / 2,
                             y: CGFloat(y + 26) + (CGFloat(height - 30) - fitHeight) / 2,
                             width: fitWidth, height: fitHeight))
        let label = NSAttributedString(string: tile.0, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.23, alpha: 1)])
        label.draw(at: NSPoint(x: CGFloat(x + 9), y: CGFloat(y + 7)))
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Contact PNG failed") }
    try! data.write(to: url)
}

private func specimen(_ count: Int) -> ForestProfile {
    var profile = ForestProfile(name: "离线验收森林")
    for index in 0..<count {
        let unlocked = ForestSpecies.allCases.filter(profile.isUnlocked)
        profile.selectedSpecies = unlocked[(index / 3) % unlocked.count]
        let suffix = String(format: "%012d", index + 1)
        profile.recordRest(id: UUID(uuidString: "00000000-0000-4000-8000-" + suffix)!, seconds: 20,
                           date: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)))
    }
    let encoded = try! JSONEncoder().encode(profile)
    var object = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object["seed"] = 108
    return try! JSONDecoder().decode(ForestProfile.self, from: JSONSerialization.data(withJSONObject: object))
}

private func compatibilitySpecimen(_ count: Int, species: ForestSpecies) -> ForestProfile {
    var profile = ForestProfile(name: "旧画面验收")
    profile.selectedSpecies = species
    for index in 0..<count {
        profile.recordRest(id: UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012d", index + 1))!,
                           seconds: 20, date: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)))
    }
    var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
    object["seed"] = 108
    return try! JSONDecoder().decode(ForestProfile.self, from: JSONSerialization.data(withJSONObject: object))
}

@MainActor
func renderEcology() {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    var trees: [(String, CGImage)] = []
    for stage in 1...3 {
        for species in ForestSpecies.allCases {
            let image = raster(CatalogueTreeIllustration(species: species, stage: stage).background(paper), width: 144, height: 184)
            let label = "\(species.title) · \(["新芽", "幼苗", "成树"][stage - 1])"
            trees.append((label, image))
            try! png(image).write(to: output.appendingPathComponent("tree-\(species.rawValue)-stage\(stage).png"))
        }
    }
    sheet(trees, columns: 6, width: 160, height: 210, to: output.appendingPathComponent("tree-stages.png"))

    let cases: [(Int, Int)] = [(35, 0), (36, 0), (48, 0), (49, 1), (49, 0), (71, 1), (72, 1), (96, 1),
        (97, 2), (97, 1), (119, 2), (120, 2), (145, 3), (145, 0), (145, 1), (145, 2)]
    for weather in [ForestWeather.sunny, .rainy] {
        var tiles: [(String, CGImage)] = []
        for item in cases {
            let image = raster(EcologySnapshot(profile: specimen(item.0), grove: item.1, weather: weather), width: 576, height: 360)
            let name = "ecology-\(item.0)-grove\(item.1 + 1)-\(weather.rawValue).png"
            try! png(image).write(to: output.appendingPathComponent(name))
            tiles.append(("\(item.0)次 · 第\(item.1 + 1)片 · \(weather.title)", image))
        }
        sheet(tiles, columns: 4, width: 384, height: 266, to: output.appendingPathComponent("milestones-\(weather.rawValue).png"))
    }

    var restPairs: [(String, CGImage)] = []
    for (count, grove) in [(36, 0), (72, 1), (120, 2)] {
        for resting in [true, false] {
            let image = raster(EcologySnapshot(profile: specimen(count), grove: grove, weather: .sunny, resting: resting),
                               width: 576, height: 360)
            restPairs.append(("\(count)次 · \(resting ? "休息中" : "休息后")", image))
        }
    }
    sheet(restPairs, columns: 2, width: 576, height: 386, to: output.appendingPathComponent("rest-versus-after.png"))

    let profile = specimen(120)
    let stillA = raster(EcologySnapshot(profile: profile, grove: 2, weather: .sunny, time: 0, reduceMotion: true), width: 576, height: 360)
    let stillB = raster(EcologySnapshot(profile: profile, grove: 2, weather: .sunny, time: 4, reduceMotion: true), width: 576, height: 360)
    precondition(png(stillA) == png(stillB), "Reduce Motion must be identical across time samples")
    try! png(stillA).write(to: output.appendingPathComponent("reduce-motion-static.png"))
    let gifURL = output.appendingPathComponent("visitors-motion.gif")
    guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, "com.compuserve.gif" as CFString, 72, nil) else {
        fatalError("Visitor GIF creation failed")
    }
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in 0..<72 {
        let image = raster(EcologySnapshot(profile: profile, grove: 2, weather: .sunny, time: Double(frame) / 12), width: 576, height: 360)
        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime: 1.0 / 12, kCGImagePropertyGIFUnclampedDelayTime: 1.0 / 12]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(gif), "Visitor GIF finalization failed")
    let compatibility = output.appendingPathComponent("compatibility-current", isDirectory: true)
    try! FileManager.default.createDirectory(at: compatibility, withIntermediateDirectories: true)
    for species in [ForestSpecies.oak, .pine, .blossom] {
        for count in [0, 1, 2, 3, 6, 12, 24] {
            for weather in [ForestWeather.sunny, .rainy] {
                let image = raster(EcologySnapshot(profile: compatibilitySpecimen(count, species: species),
                    grove: 0, weather: weather), width: 576, height: 360)
                try! png(image).write(to: compatibility.appendingPathComponent("\(species.rawValue)-\(count)-\(weather.rawValue).png"))
            }
        }
    }
    print("Rendered all six species × three stages, ecology boundaries, retained groves, rest/after, and motion samples: \(output.path)")
}
MainActor.assumeIsolated { renderEcology() }
"""#
let main = destination.appendingPathComponent("main.swift")
try (art + "\n" + scene + "\n" + catalogueArt + "\n" + harness).write(to: main, atomically: true, encoding: .utf8)
let executable = destination.appendingPathComponent("render-ecology")
try execute(["swiftc", "-module-cache-path", cache.path, main.path, "-I", destination.path, "-L", destination.path,
             "-lPomodoroCore", "-Xlinker", "-rpath", "-Xlinker", destination.path, "-o", executable.path])
let process = Process()
process.executableURL = executable
process.arguments = [destination.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }

// Compare the original three species against the released 0.10.0 Canvas at
// identical seeds, trees, clocks and weather. The baseline is read-only git data.
func gitText(_ arguments: [String]) throws -> String {
    let task = Process(); let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    task.arguments = ["-C", project.path] + arguments
    task.standardOutput = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "EcologyBaseline", code: Int(task.terminationStatus))
    }
    return text
}
let baselineCommit = "efd76de"
let baseline = destination.appendingPathComponent("compatibility-baseline", isDirectory: true)
let baselineCore = baseline.appendingPathComponent("core", isDirectory: true)
try fm.createDirectory(at: baselineCore, withIntermediateDirectories: true)
let oldCorePaths = try gitText(["ls-tree", "-r", "--name-only", baselineCommit, "Sources/PomodoroCore"])
    .split(separator: "\n").map(String.init).filter { $0.hasSuffix(".swift") }
var oldCoreSources: [String] = []
for path in oldCorePaths {
    let url = baselineCore.appendingPathComponent((path as NSString).lastPathComponent)
    try gitText(["show", baselineCommit + ":" + path]).write(to: url, atomically: true, encoding: .utf8)
    oldCoreSources.append(url.path)
}
try execute(["swiftc", "-module-cache-path", cache.path, "-emit-module", "-emit-library", "-module-name", "PomodoroCore"] + oldCoreSources +
            ["-o", baseline.appendingPathComponent("libPomodoroCore.dylib").path])
let oldScene = try gitText(["show", baselineCommit + ":Sources/BreaktimeApp/ForestSceneView.swift"])
let oldHarness = #"""
import AppKit
import ImageIO
private struct BaselineScene: View {
    let profile: ForestProfile
    let weather: ForestWeather
    var body: some View {
        Canvas { context, size in
            var painter = ForestPixelPainter(context: context, size: size, time: 0,
                seed: profile.seed, resting: false, climate: ForestAtmosphere(weather: weather))
            painter.paint(profile: profile, groveIndex: 0, progress: 0)
        }.background(Color(red: 0.97, green: 0.96, blue: 0.91))
    }
}
private func specimen(_ count: Int, species: ForestSpecies) -> ForestProfile {
    var profile = ForestProfile(name: "旧画面验收")
    profile.selectedSpecies = species
    for index in 0..<count {
        profile.recordRest(id: UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012d", index + 1))!,
                          seconds: 20, date: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)))
    }
    var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
    object["seed"] = 108
    return try! JSONDecoder().decode(ForestProfile.self, from: JSONSerialization.data(withJSONObject: object))
}
@MainActor
func renderBaseline() {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    // Warm the same Canvas/gradient pipelines before retaining a comparison
    // sample; the current renderer has already drawn its contact sheets.
    for _ in 0..<2 {
    for species in [ForestSpecies.oak, .pine, .blossom] {
        for count in [0, 1, 2, 3, 6, 12, 24] {
            for weather in [ForestWeather.sunny, .rainy] {
                let renderer = ImageRenderer(content: BaselineScene(profile: specimen(count, species: species), weather: weather)
                    .frame(width: 576, height: 360))
                renderer.proposedSize = ProposedViewSize(width: 576, height: 360); renderer.scale = 1
                guard let image = renderer.cgImage else { fatalError("Baseline Canvas failed") }
                let url = output.appendingPathComponent("\(species.rawValue)-\(count)-\(weather.rawValue).png")
                let target = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(target, image, nil)
                precondition(CGImageDestinationFinalize(target))
            }
        }
    }
    }
}
MainActor.assumeIsolated { renderBaseline() }
"""#
let oldMain = baseline.appendingPathComponent("main.swift")
try (oldScene + "\n" + oldHarness).write(to: oldMain, atomically: true, encoding: .utf8)
let oldExecutable = baseline.appendingPathComponent("render-baseline")
try execute(["swiftc", "-module-cache-path", cache.path, oldMain.path, "-I", baseline.path, "-L", baseline.path,
             "-lPomodoroCore", "-Xlinker", "-rpath", "-Xlinker", baseline.path, "-o", oldExecutable.path])
let oldProcess = Process(); oldProcess.executableURL = oldExecutable; oldProcess.arguments = [baseline.path]
try oldProcess.run(); oldProcess.waitUntilExit()
guard oldProcess.terminationStatus == 0 else { exit(oldProcess.terminationStatus) }
let currentImages = destination.appendingPathComponent("compatibility-current", isDirectory: true)
let names = try fm.contentsOfDirectory(atPath: currentImages.path).filter { $0.hasSuffix(".png") }.sorted()
var differences: [String] = []
for name in names {
    let old = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(baseline.appendingPathComponent(name) as CFURL, nil)!, 0, nil)!
    let new = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(currentImages.appendingPathComponent(name) as CFURL, nil)!, 0, nil)!
    if old.width != new.width || old.height != new.height || (old.dataProvider!.data! as Data) != (new.dataProvider!.data! as Data) {
        differences.append(name)
    }
}
let report: [String: Any] = ["baselineCommit": baselineCommit, "samples": names.count,
                           "identical": names.count - differences.count, "differences": differences]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: destination.appendingPathComponent("compatibility-report.json"))
print("Old forest Canvas compatibility: \(names.count - differences.count)/\(names.count) identical pixel samples")
guard differences.isEmpty else { throw NSError(domain: "EcologyBaseline", code: 2) }
