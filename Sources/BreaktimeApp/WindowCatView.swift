import SwiftUI
import PomodoroCore
import ImageIO

private final class WindowCatAtlas {
    struct Manifest: Decodable {
        let frameCount: Int
        let fps: Double
        let width: Int
        let height: Int
    }
    let manifest: Manifest
    let frames: [CGImage]
    static let shared: WindowCatAtlas? = load()

    private init(manifest: Manifest, frames: [CGImage]) {
        self.manifest = manifest
        self.frames = frames
    }

    private static func load() -> WindowCatAtlas? {
        guard let folder = RestCatAssets.windowDirectory,
              let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let metadata = try? JSONDecoder().decode(Manifest.self, from: data),
              (2...120).contains(metadata.frameCount), (1...30).contains(metadata.fps),
              metadata.width > 0, metadata.height > 0 else { return nil }
        var frames: [CGImage] = []
        for index in 0..<metadata.frameCount {
            let url = folder.appendingPathComponent(String(format: "%04d.png", index))
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            frames.append(image)
        }
        return WindowCatAtlas(manifest: metadata, frames: frames)
    }
}

/// The display becomes a pane of glass. A large photographic cat rests behind it;
/// pointer motion gives a small lean, while a tap elicits a brief close-up response.
struct WindowCatView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date()
    @State private var pointer: CGPoint?
    @State private var lastTouch: Date?
    @State private var touchPoint: CGPoint?
    private let warmWhite = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let ink = Color(red: 0.30, green: 0.22, blue: 0.16)

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { timeline in
                let elapsed = max(0, timeline.date.timeIntervalSince(appearedAt))
                let touchAge = lastTouch.map { max(0, timeline.date.timeIntervalSince($0)) }
                let responding = touchAge.map { $0 < 2.7 } ?? false
                ZStack {
                    // A subtle light pool behind the fur keeps this a window,
                    // with no rectangle around the photographic subject.
                    RadialGradient(colors: [Color(red: 1, green: 0.83, blue: 0.61).opacity(0.18), .clear],
                        center: UnitPoint(x: 0.5, y: 0.57),
                        startRadius: 10, endRadius: max(geometry.size.width, geometry.size.height) * 0.57)
                        .allowsHitTesting(false)

                    Canvas { context, size in
                        paintCat(context, size: size, elapsed: elapsed, touchAge: touchAge)
                    }
                    .accessibilityLabel("一只大眼睛小橘猫扒着窗沿，好奇地抬头张望")

                    // Reflections live on the pane in front of the cat.
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.07), location: 0),
                        .init(color: .clear, location: 0.28),
                        .init(color: .clear, location: 0.69),
                        .init(color: .white.opacity(0.035), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)

                    if !reduceMotion, let age = touchAge, age < 1.1, let point = touchPoint {
                        let progress = min(1, age / 1.1)
                        Circle().stroke(ink.opacity((1 - progress) * 0.3), lineWidth: 1.2)
                            .frame(width: 28 + progress * 160, height: 28 + progress * 160)
                            .position(point)
                            .allowsHitTesting(false)
                        Circle().fill(warmWhite.opacity((1 - progress) * 0.13))
                            .frame(width: 20 + progress * 70, height: 20 + progress * 70)
                            .position(point).blur(radius: 7).allowsHitTesting(false)
                    }

                    // The sill conceals the lower torso so the cat feels close
                    // to the glass, rather than pasted in the middle of a canvas.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(.white.opacity(0.7)).frame(height: 2)
                        LinearGradient(colors: [Color(red: 0.94, green: 0.87, blue: 0.75).opacity(0.88),
                                                Color(red: 0.78, green: 0.68, blue: 0.55).opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: max(65, geometry.size.height * 0.10))
                    }.allowsHitTesting(false)

                    // Let the kitten's real front paws hang over the sill. Only
                    // the bottom strip is painted in front of the window frame.
                    Canvas { context, size in
                        paintCat(context, size: size, elapsed: elapsed, touchAge: touchAge)
                    }
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: max(65, geometry.size.height * 0.10))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(responding ? "叩叩，收到啦！" : "喵，抬头看看远处吧。")
                            .font(.system(size: geometry.size.width < 800 ? 22 : 29,
                                          weight: .medium, design: .rounded))
                            .foregroundStyle(ink)
                            .shadow(color: .white.opacity(0.25), radius: 12)
                        Text(responding ? "先让眼睛歇一会儿，猫猫等你回来" : "轻点玻璃，和猫猫打个招呼")
                            .font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, max(28, geometry.size.width * 0.035))
                    .padding(.top, max(35, geometry.size.height * 0.055))
                    .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.55), lineWidth: 1)
                        .padding(12).allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): pointer = point
                    case .ended: pointer = nil
                    }
                }
                .gesture(SpatialTapGesture().onEnded { tap in
                    touchPoint = tap.location
                    lastTouch = Date()
                })
                .accessibilityAction(named: "轻敲玻璃") {
                    touchPoint = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.52)
                    lastTouch = Date()
                }
                .task(id: lastTouch) {
                    guard let touched = lastTouch else { return }
                    do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                    catch { return }
                    if lastTouch == touched {
                        lastTouch = nil
                        touchPoint = nil
                    }
                }
            }
        }
    }

    private func paintCat(_ context: GraphicsContext, size: CGSize,
                          elapsed: TimeInterval, touchAge: TimeInterval?) {
        guard let atlas = WindowCatAtlas.shared else { return }
        let scene = CatWindowScene(width: size.width, height: size.height,
            imageAspectRatio: Double(atlas.manifest.width) / Double(atlas.manifest.height))
        let pose = scene.pose(pointerX: reduceMotion ? nil : pointer.map { Double($0.x) },
            pointerY: reduceMotion ? nil : pointer.map { Double($0.y) },
            elapsed: reduceMotion ? 0 : elapsed,
            timeSinceTouch: reduceMotion ? nil : touchAge)
        let cycle = atlas.frames.count * 2 - 2
        let poster = atlas.frames.count / 2
        let step = reduceMotion ? poster : (Int(elapsed * atlas.manifest.fps) + poster) % cycle
        let frame = step < atlas.frames.count ? step : cycle - step
        var drawing = context
        drawing.translateBy(x: pose.centerX, y: pose.centerY)
        drawing.rotate(by: .degrees(pose.rotationDegrees))
        drawing.scaleBy(x: pose.scale, y: pose.scale)
        drawing.draw(Image(decorative: atlas.frames[frame], scale: 1),
            in: CGRect(x: -pose.width / 2, y: -pose.height / 2,
                       width: pose.width, height: pose.height))
    }
}
