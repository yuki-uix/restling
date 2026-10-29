import AppKit
import Foundation

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("Usage: generate-icon.swift /absolute/path/AppIcon.iconset [source.png]\n", stderr)
    exit(2)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let source = CommandLine.arguments.count == 3
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : projectDirectory.appendingPathComponent("Resources/RestlingIcon.png")

guard let artwork = NSImage(contentsOf: source), artwork.isValid else {
    fputs("Cannot read Restling icon artwork: \(source.path)\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

// Compile the finished square master into macOS icon representations. Applying
// one vector mask at each destination size keeps transparent corners clean.
func renderIcon(pixels: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "RestlingIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot allocate icon bitmap."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    graphics.cgContext.clear(canvas)
    graphics.cgContext.setShouldAntialias(true)
    graphics.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    graphics.imageInterpolation = .high

    let tile = NSRect(x: 48, y: 48, width: 928, height: 928)
    NSBezierPath(roundedRect: tile, xRadius: 208, yRadius: 208).addClip()
    artwork.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

    graphics.flushGraphics()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RestlingIcon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon PNG."])
    }
    try data.write(to: destination.appendingPathComponent(name), options: .atomic)
}

for size in [16, 32, 128, 256, 512] {
    try renderIcon(pixels: size, name: "icon_\(size)x\(size).png")
    try renderIcon(pixels: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
