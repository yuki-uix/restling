import SwiftUI
import PomodoroCore

/// Original, code-drawn pixel scenery. The desktop material remains visible
/// around the island; no bitmap background or remote asset is required.
struct ForestSceneView: View {
    let profile: ForestProfile
    var resting: Bool = false
    var progress: Double = 0
    var groveIndex: Int? = nil
    var weather: ForestWeather? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date()
    @State private var previousOverride: ForestWeather?
    @State private var overrideTransitionFrom: ForestAtmosphere?
    @State private var overrideChangedAt = Date.distantPast

    private var totalLandscape: ForestLandscape { ForestLandscape(profile: profile) }
    private var displayedGroveIndex: Int {
        min(max(0, groveIndex ?? totalLandscape.currentGroveIndex), totalLandscape.groveCount - 1)
    }
    private var localLandscape: ForestLandscape {
        ForestLandscape(completedRests: totalLandscape.rests(inGrove: displayedGroveIndex))
    }
    private var groveSeed: UInt64 {
        // An established grove keeps its identity. Later groves get a stable
        // different orientation without shifting anything in the previous one.
        profile.seed &+ UInt64(displayedGroveIndex) &* 0x9E3779B97F4A7C15
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let elapsed = reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(appearedAt))
                var painter = ForestPixelPainter(context: context, size: size, time: elapsed,
                                                 seed: groveSeed, resting: resting,
                                                 climate: atmosphere(at: timeline.date))
                painter.paint(profile: profile, groveIndex: displayedGroveIndex,
                              progress: min(1, max(0, progress)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profile.name)的像素森林")
        .accessibilityValue("第 \(displayedGroveIndex + 1) 片林地，\(localLandscape.stageTitle)，这里已种下 \(localLandscape.visibleTreeCount) 棵树。\(localLandscape.nextMilestoneText)")
        .onAppear { previousOverride = weather }
        .onChange(of: weather) { newValue in
            let now = Date()
            let old = targetAtmosphere(for: previousOverride, at: now)
            if let from = overrideTransitionFrom, !reduceMotion {
                let fraction = min(1, max(0, now.timeIntervalSince(overrideChangedAt) / 2))
                overrideTransitionFrom = ForestAtmosphere.blending(from: from, to: old, progress: fraction)
            } else { overrideTransitionFrom = old }
            previousOverride = newValue
            overrideChangedAt = now
        }
    }

    private func targetAtmosphere(for choice: ForestWeather?, at date: Date) -> ForestAtmosphere {
        if let choice { return ForestAtmosphere(weather: choice) }
        let clock = reduceMotion ? appearedAt : date
        return ForestAtmosphere.sample(at: clock.timeIntervalSinceReferenceDate, seed: profile.seed)
    }

    private func atmosphere(at date: Date) -> ForestAtmosphere {
        let target = targetAtmosphere(for: weather, at: date)
        guard !reduceMotion, let from = overrideTransitionFrom else { return target }
        let fraction = min(1, max(0, date.timeIntervalSince(overrideChangedAt) / 2))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return ForestAtmosphere.blending(from: from, to: target, progress: eased)
    }
}

private struct ForestPixelPainter {
    var context: GraphicsContext
    let time: Double
    let seed: UInt64
    let resting: Bool
    let climate: ForestAtmosphere

    private let deep = Color.pixel(0x275044)
    private let moss = Color.pixel(0x57845B)
    private let grass = Color.pixel(0x9BBE78)
    private let sunlight = Color.pixel(0xCFDFA0)
    private let cream = Color.pixel(0xFBF1CF)
    private let bark = Color.pixel(0x755845)

    init(context: GraphicsContext, size: CGSize, time: Double, seed: UInt64, resting: Bool,
         climate: ForestAtmosphere) {
        self.context = context
        self.time = time
        self.seed = seed
        self.resting = resting
        self.climate = climate
        let scale = min(size.width / 384, size.height / 216)
        self.context.translateBy(x: (size.width - 384 * scale) / 2,
                                 y: (size.height - 216 * scale) / 2)
        self.context.scaleBy(x: scale, y: scale)
    }

    mutating func paint(profile: ForestProfile, groveIndex: Int, progress: Double) {
        let total = ForestLandscape(profile: profile)
        let landscape = ForestLandscape(completedRests: total.rests(inGrove: groveIndex))
        // Each profile has a fixed orientation. Trees never change their position
        // when another rest is completed, and no ambient trees are gifted.
        if seed & 1 == 1 {
            context.translateBy(x: 384, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        atmosphere(landscape: landscape)
        island(landscape: landscape)
        if landscape.hasStream { stream(landscape: landscape) }
        groundDetails(landscape: landscape)

        let sites: [(Double, Double)] = [
            (197, 153), (166, 159), (228, 157), (195, 177),
            (144, 143), (247, 145), (127, 169), (267, 170),
            (160, 185), (230, 186), (107, 151), (287, 154),
            (170, 126), (226, 126), (91, 179), (301, 181)
        ]
        let earned = Array(profile.trees.dropFirst(groveIndex * sites.count).prefix(sites.count))
        let plantingIndex = min(earned.count, sites.count - 1)
        let planting = sites[plantingIndex]
        // Empty soil is meaningful: at 0 and every multiple of 3 there is no
        // automatic next sprout. Only completed rests reveal living plants.
        if earned.count < sites.count {
            currentPlot(x: planting.0, y: planting.1, stage: 0,
                        species: profile.selectedSpecies, progress: progress)
        }
        var drawOrder: [(index: Int, y: Double)] = earned.indices.map { ($0, sites[$0].1) }
        if landscape.hasCurrentPlant && groveIndex == total.currentGroveIndex && earned.count < sites.count {
            drawOrder.append((earned.count, planting.1))
        }
        for item in drawOrder.sorted(by: { $0.y < $1.y }) {
            if item.index < earned.count {
                let planted = earned[item.index]
                let site = sites[item.index]
                tree(planted.species, x: site.0, y: site.1,
                     scale: item.index < 4 ? 0.62 : 0.53, variation: item.index + 10)
            } else {
                currentPlot(x: planting.0, y: planting.1, stage: landscape.completedRests % 3,
                            species: profile.selectedSpecies, progress: progress)
            }
        }
        if landscape.hasFlowers {
            flowers(x: 147, y: 173, pink: seed & 8 == 0)
            flowers(x: 236, y: 175, pink: seed & 8 != 0)
            butterfly(x: 218, y: 106, phase: 0)
        }
        if landscape.hasMushrooms {
            mushroom(x: 109, y: 182, tiny: false)
            mushroom(x: 117, y: 185, tiny: true)
            mushroom(x: 282, y: 167, tiny: true)
            flowers(x: 286, y: 186, pink: true)
        }
        weatherOnLand(landscape: landscape)
        windWisps()
        rain(landscape: landscape)
        if resting && climate.rainIntensity < 0.1 { motes() }
    }

    private func atmosphere(landscape: ForestLandscape) {
        // A local, feathered sky makes weather readable even before the first
        // plant appears. Its edges stay transparent over the desktop material.
        softEllipse(28, 30, 328, 181,
                    color: Color.pixel(0xE3B65C).opacity(climate.sunStrength * 0.25))
        softEllipse(35, 32, 314, 178,
                    color: Color.pixel(0x8EAFBF).opacity(climate.cloudCover * 0.25 + climate.rainIntensity * 0.15))

        let sun = climate.sunStrength * max(0, 1 - climate.rainIntensity * 2)
        let sunX = 261 + sin(time * 0.16) * 3
        softEllipse(sunX - 35, 22, 70, 70,
                    color: Color.pixel(0xF5CE78).opacity(sun * 0.35))
        oval(sunX - 12, 45, 24, 24, color: Color.pixel(0xEFC873).opacity(sun * 0.90), step: 2)
        rect(sunX - 1, 36, 3, 4, cream.opacity(sun * 0.90))
        rect(sunX - 1, 75, 3, 4, cream.opacity(sun * 0.90))
        rect(sunX - 21, 55, 4, 3, cream.opacity(sun * 0.90))
        rect(sunX + 18, 55, 4, 3, cream.opacity(sun * 0.90))

        // Broad, soft rays and a matching patch on the ground drift together.
        let beamDrift = sin(time * 0.36) * 20
        let beamOpacity = sun * (resting ? 0.10 : 0.15)
        for index in 0..<3 {
            let dx = Double(index) * 34 + beamDrift
            var ray = Path()
            ray.move(to: .init(x: 226 + dx, y: 67))
            ray.addLine(to: .init(x: 238 + dx, y: 67))
            ray.addLine(to: .init(x: 187 + dx, y: 191))
            ray.addLine(to: .init(x: 146 + dx, y: 191))
            ray.closeSubpath()
            context.fill(ray, with: .linearGradient(
                Gradient(colors: [Color.pixel(0xFFF0B9).opacity(beamOpacity),
                                  Color.pixel(0xFFE1A0).opacity(beamOpacity * 0.7), .clear]),
                startPoint: .init(x: 239 + dx, y: 69), endPoint: .init(x: 172 + dx, y: 199)))
        }

        // Two drifting depths move several screen pixels within two seconds.
        // Clouds wrap only after their feathered edge has left the sky stage.
        // Speeds are fixed: a later weather fade must not multiply accumulated
        // time by a new speed and make a long-open scene jump.
        driftingCloud(baseX: 71, y: 68, scale: 0.88, speed: 3.6,
                      opacity: 0.60 + climate.cloudCover * 0.25)
        driftingCloud(baseX: 232, y: 89, scale: 0.61, speed: 1.9,
                      opacity: 0.40 + climate.cloudCover * 0.35)
        if climate.cloudCover > 0.20 {
            driftingCloud(baseX: 154, y: 44, scale: 1.26, speed: 1.7,
                          opacity: (climate.cloudCover - 0.20) * 1.18)
            driftingCloud(baseX: 277, y: 61, scale: 0.91, speed: 2.35,
                          opacity: (climate.cloudCover - 0.20) * 0.83)
        }
        if climate.rainIntensity > 0.001 {
            // Feathered mist connects cloud and shower without a visible panel
            // edge. The actual rain threads remain crisp enough to read.
            softEllipse(61, 75, 266, 131,
                        color: Color.pixel(0x93B7C4).opacity(climate.rainIntensity * 0.19))
        }
        let width = 314 * landscape.landScale
        oval(194 - width * 0.44, 177 + landscape.expansionProgress * 27,
             width * 0.88, 9, color: deep.opacity(0.05), step: 3)
    }

    private func driftingCloud(baseX: Double, y: Double, scale: Double, speed: Double, opacity: Double) {
        let x = (baseX + time * speed + 95).truncatingRemainder(dividingBy: 500) - 95
        let edge = max(0, min(1, (x + 72) / 38, (406 - x) / 38))
        cloud(x: x, y: y, scale: scale, opacity: min(1, opacity) * edge)
    }

    private func cloud(x: Double, y: Double, scale: Double, opacity: Double) {
        let overcast = climate.cloudCover
        let c = Color(.sRGB, red: 1 - overcast * 0.35, green: 0.98 - overcast * 0.27,
                      blue: 0.91 - overcast * 0.12, opacity: opacity)
        let shapes: [(Double, Double, Double, Double)] = [
            (0, 11, 55, 11), (7, 5, 42, 17), (18, 0, 22, 22),
            (46, 14, 15, 8), (-7, 14, 12, 8)
        ]
        for s in shapes { rect(x + s.0 * scale, y + s.1 * scale, s.2 * scale, s.3 * scale, c) }
        rect(x + 13 * scale, y + 5 * scale, 19 * scale, 3 * scale,
             Color.pixel(0xEAF2E9).opacity(opacity * 0.42))
        rect(x + 3 * scale, y + 20 * scale, 48 * scale, 2 * scale,
             Color.pixel(0x789AA8).opacity(opacity * overcast * 0.28))
    }

    private func landOutline(_ landscape: ForestLandscape) -> [CGPoint] {
        let widthScale = landscape.landScale
        let heightScale = (38 + 66 * landscape.expansionProgress) / 104
        let outline: [CGPoint] = [
            .init(x: 59, y: 115), .init(x: 101, y: 107), .init(x: 136, y: 99),
            .init(x: 246, y: 101), .init(x: 287, y: 111), .init(x: 321, y: 122),
            .init(x: 348, y: 141), .init(x: 350, y: 162), .init(x: 331, y: 181),
            .init(x: 295, y: 193), .init(x: 249, y: 201), .init(x: 151, y: 201),
            .init(x: 99, y: 194), .init(x: 65, y: 181), .init(x: 40, y: 161),
            .init(x: 38, y: 142)
        ]
        return outline.map { .init(x: (194 + ($0.x - 194) * widthScale).rounded(),
                                    y: (154 + ($0.y - 150) * heightScale).rounded()) }
    }

    private func island(landscape: ForestLandscape) {
        let outline = landOutline(landscape)
        polygon(outline.map { CGPoint(x: $0.x, y: $0.y + 8) }, color: Color.pixel(0x846A50))
        polygon(outline.map { CGPoint(x: $0.x, y: $0.y + 4) }, color: Color.pixel(0xB08B5C))
        polygon(outline, color: Color.pixel(0xCBB082))
        var ground = self
        ground.context.clip(to: outlinePath(outline))
        if landscape.completedRests >= 3 {
            ground.polygon(outline, color: grass)
            ground.oval(141, 134, 111, 46, color: Color.pixel(0xB4CC87), step: 4)
        } else if landscape.hasVegetation {
            let width = 27 + Double(landscape.completedRests) * 9
            ground.oval(197 - width / 2, 141, width, 22,
                        color: Color.pixel(0xABB979), step: 3)
        }
        let count = landscape.hasVegetation ? 8 + landscape.completedRests * 2 : 7
        for index in 0..<min(48, count) {
            let x = 194 + (stable(index + 40) - 0.5) * 290 * landscape.landScale
            let y = 154 + (stable(index + 130) - 0.5) * (30 + 62 * landscape.expansionProgress)
            if abs(x - 197) < 16 && abs(y - 153) < 9 { continue }
            let c = landscape.hasVegetation ? moss.opacity(0.42) : Color.pixel(0xAD8A60).opacity(0.65)
            ground.rect(x.rounded(), y.rounded(), 3, 1, c)
            if landscape.completedRests >= 3 && index % 3 == 0 {
                let tip = (sin(time * 1.08 + Double(index) * 0.28) * climate.windStrength * 2).rounded()
                ground.rect(x.rounded() + 1, y.rounded() - 2, 1, 3, moss.opacity(0.46))
                ground.rect(x.rounded() + 1 + tip, y.rounded() - 3, 1, 1, moss.opacity(0.46))
            }
        }
        // The dark soil edge makes even the empty first patch deliberate.
        let left = outline.map(\.x).min() ?? 152
        rect(left + 12, 167 + landscape.expansionProgress * 27, 9, 2, Color.pixel(0xC9A777))
        if landscape.completedRests >= 6 {
            rect(203, 171, 9, 3, Color.pixel(0xD4D19F))
            stone(x: 204, y: 172, width: 8)
        }
    }

    private func stream(landscape: ForestLandscape) {
        let river = Color.pixel(0x80B6AE)
        let light = Color.pixel(0xB8DAD0)
        let halfWidth = 314 * landscape.landScale / 2
        let halfHeight = (38 + 66 * landscape.expansionProgress) / 2
        let bottom = 154 + halfHeight * sqrt(max(0, 1 - pow(63 / halfWidth, 2)))
        rect(119, 146, 20, 7, river)
        rect(125, 153, 22, 8, river)
        rect(132, 161, 20, 8, river)
        rect(127, 169, 21, 8, river)
        rect(129, 177, 15, max(7, bottom - 177), river)
        rect(131, bottom, 9, 11, light.opacity(0.74))
        rect(132, bottom + 11, 7, 4, light.opacity(0.3))
        let ripple = Int(time * 0.7) % 2 == 0 ? 0.0 : 3.0
        rect(127 + ripple, 151, 9, 1, light)
        rect(136 - ripple, 163, 8, 1, light)
        rect(132 + ripple, 177, 8, 1, light)
        stone(x: 135, y: 166, width: 8)
        stone(x: 126, y: 162, width: 7)
    }

    private func groundDetails(landscape: ForestLandscape) {
        // Stone markers and a little sign can exist before the first plant.
        stone(x: 211, y: 157, width: 5)
        if landscape.completedRests >= 3 {
            rect(214, 163, 2, 10, bark)
            rect(210, 161, 11, 4, Color.pixel(0xB99862))
            rect(211, 162, 7, 1, cream.opacity(0.38))
        }
        if landscape.completedRests >= 12 {
            rect(253, 178, 18, 4, bark)
            rect(254, 176, 18, 4, Color.pixel(0xB18D5D))
            rect(255, 179, 2, 5, bark)
            rect(267, 179, 2, 5, bark)
            rect(255, 177, 13, 1, cream.opacity(0.35))
        }
    }

    private func currentPlot(x: Double, y: Double, stage: Int,
                             species: ForestSpecies, progress: Double) {
        var local = self
        local.context.translateBy(x: x - 197, y: y - 153)
        local.oval(181, 149, 32, 10, color: Color.pixel(0xB49A6E).opacity(0.4), step: 2)
        local.oval(184, 149, 26, 8, color: Color.pixel(0x947750), step: 2)
        local.oval(189, 150, 16, 4, color: Color.pixel(0xBC9D69), step: 1)
        if stage == 1 {
            local.rect(196, 144, 2, 9, Color.pixel(0x608050))
            var leaves = local
            let bend = (sin(time * 1.08) * climate.windStrength * 1.6 * 2).rounded() / 2
            leaves.context.translateBy(x: bend, y: 0)
            leaves.rect(191, 141, 6, 4, Color.pixel(0x7DA862))
            leaves.rect(188, 140, 5, 2, Color.pixel(0xAAC47B))
            leaves.rect(198, 138, 6, 4, Color.pixel(0x699C54))
            leaves.rect(202, 137, 4, 2, Color.pixel(0xB2CD86))
        } else if stage == 2 {
            local.tree(species, x: 197, y: 153, scale: 0.39, variation: 27)
        }
        local.rect(180, 152, 3, 2, cream.opacity(0.85))
        local.rect(211, 152, 3, 2, cream.opacity(0.85))
        local.rect(187, 157, 3, 2, cream.opacity(0.72))
        local.rect(205, 157, 3, 2, cream.opacity(0.72))
        if resting {
            let pulse = 0.25 + 0.14 * sin(time * 0.6)
            local.sparkle(x: 182, y: 137, opacity: pulse)
            local.sparkle(x: 212, y: 132, opacity: 0.34 - pulse * 0.35)
        }
    }

    private func outlinePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func tree(_ species: ForestSpecies, x: Double, y: Double, scale: Double, variation: Int) {
        var local = self
        // The trunk stays planted. A coherent 5–6 second breeze crosses the
        // canopy, with enough travel to read at the small dashboard scale.
        let gust = 0.72 + sin(time * 0.31) * 0.28
        let amplitude = (0.45 + climate.windStrength * 3.8) * gust
        let sway = (sin(time * 1.08 + Double(variation) * 0.28) * amplitude * 4).rounded() / 4
        local.context.translateBy(x: x.rounded(), y: y.rounded())
        local.context.scaleBy(x: scale, y: scale)
        local.oval(-17, -4, 34, 9, color: deep.opacity(0.13), step: 3)
        local.rect(-3, -29, 6, 30, bark)
        local.rect(0, -27, 2, 26, Color.pixel(0xA47D51))
        local.rect(-6, -2, 11, 3, bark)
        local.rect(-5, -22, 3, 6, bark)
        local.rect(3, -27, 5, 3, bark)
        local.context.translateBy(x: sway, y: 0)
        switch species {
        case .oak: local.oak()
        case .pine: local.pine()
        case .blossom: local.blossom()
        }
    }

    private func oak() {
        oval(-25, -63, 49, 43, color: Color.pixel(0x3C6C4E), step: 5)
        oval(-29, -52, 22, 25, color: Color.pixel(0x3C6C4E), step: 4)
        oval(10, -52, 20, 24, color: Color.pixel(0x3C6C4E), step: 4)
        oval(-22, -65, 42, 33, color: Color.pixel(0x6C995B), step: 4)
        oval(-24, -54, 24, 22, color: Color.pixel(0x6C995B), step: 4)
        oval(1, -58, 23, 23, color: Color.pixel(0x7DA667), step: 4)
        oval(-15, -65, 28, 19, color: Color.pixel(0x94B976), step: 4)
        rect(-13, -61, 9, 4, Color.pixel(0xB7CD83))
        rect(-19, -52, 6, 3, Color.pixel(0xA9C17B))
        rect(7, -52, 6, 3, Color.pixel(0xA9C17B))
        rect(-6, -35, 6, 3, Color.pixel(0x558150))
        rect(13, -39, 4, 3, Color.pixel(0x9AB56D))
    }

    private func pine() {
        let shadow = Color.pixel(0x345E4D)
        let mid = Color.pixel(0x58896A)
        let bright = Color.pixel(0x81A67A)
        steppedPine(top: -76, width: 18, height: 28, color: shadow)
        steppedPine(top: -61, width: 29, height: 30, color: shadow)
        steppedPine(top: -43, width: 40, height: 27, color: shadow)
        steppedPine(top: -76, width: 12, height: 25, color: mid)
        steppedPine(top: -61, width: 22, height: 27, color: mid)
        steppedPine(top: -43, width: 31, height: 22, color: mid)
        rect(-2, -71, 3, 7, bright)
        rect(-7, -55, 6, 3, bright)
        rect(-13, -36, 8, 3, bright)
        rect(4, -29, 6, 2, bright.opacity(0.65))
    }

    private func steppedPine(top: Double, width: Double, height: Double, color: Color) {
        let rows = Int(height / 4)
        for i in 0..<rows {
            let rowWidth = max(4, (width * Double(i + 1) / Double(rows) / 2).rounded() * 2)
            rect(-rowWidth / 2, top + Double(i) * 4, rowWidth, 4, color)
        }
    }

    private func blossom() {
        oval(-25, -61, 50, 39, color: Color.pixel(0xAD7B84), step: 4)
        oval(-28, -53, 24, 24, color: Color.pixel(0xBD8C93), step: 4)
        oval(-22, -64, 43, 34, color: Color.pixel(0xD9A6A7), step: 4)
        oval(1, -58, 24, 24, color: Color.pixel(0xE7BAB5), step: 4)
        oval(-14, -64, 26, 19, color: Color.pixel(0xF0CDC0), step: 4)
        rect(-15, -57, 5, 3, Color.pixel(0xFAE2CA))
        rect(7, -50, 5, 3, Color.pixel(0xFAE2CA))
        rect(-4, -40, 4, 3, Color.pixel(0xF0CDC0))
        rect(12, -32, 3, 3, Color.pixel(0xD9A6A7))
    }

    private func shrub(x: Double, y: Double, shade: Int) {
        let c = shade == 0 ? Color.pixel(0x6A965E) : Color.pixel(0x83A76C)
        oval(x - 11, y - 10, 23, 12, color: moss, step: 3)
        oval(x - 10, y - 12, 18, 12, color: c, step: 3)
        rect(x - 6, y - 10, 5, 2, sunlight.opacity(0.58))
    }

    private func stone(x: Double, y: Double, width: Double) {
        rect(x, y, width, 3, Color.pixel(0x8F9B82))
        rect(x + 1, y - 2, width - 2, 3, Color.pixel(0xC2C8AC))
        rect(x + 2, y - 2, width - 4, 1, Color.pixel(0xE4DEBC))
    }

    private func flowers(x: Double, y: Double, pink: Bool) {
        let c = pink ? Color.pixel(0xDAA89B) : Color.pixel(0xF8E7AF)
        for i in 0..<3 {
            let dx = Double(i * 5)
            let dy = i % 2 == 0 ? 0.0 : -3.0
            rect(x + dx + 1, y + dy, 1, 4, moss)
            let sway = (sin(time * 1.08 + Double(i) * 0.28) * climate.windStrength * 2).rounded()
            rect(x + dx + sway, y + dy - 2, 3, 3, c)
            rect(x + dx + 1 + sway, y + dy - 1, 1, 1, Color.pixel(0xBD9761))
        }
    }

    private func mushroom(x: Double, y: Double, tiny: Bool) {
        let scale = tiny ? 0.65 : 1.0
        rect(x, y - 5 * scale, 3 * scale, 6 * scale, cream)
        rect(x - 3 * scale, y - 8 * scale, 9 * scale, 4 * scale, Color.pixel(0xC87D67))
        rect(x - 1 * scale, y - 10 * scale, 5 * scale, 3 * scale, Color.pixel(0xD99A78))
        rect(x - 1 * scale, y - 8 * scale, 2 * scale, 1 * scale, cream)
    }

    private func butterfly(x: Double, y: Double, phase: Double) {
        let dx = sin(time * 0.24 + phase) * 11
        let dy = cos(time * 0.35 + phase) * 5
        let open = sin(time * 2 + phase) > 0 ? 3.0 : 1.0
        rect((x + dx).rounded(), (y + dy).rounded(), 1, 4, Color.pixel(0x897953))
        rect((x + dx - open).rounded(), (y + dy - 1).rounded(), open, 3, Color.pixel(0xF5DF9B))
        rect((x + dx + 1).rounded(), (y + dy - 1).rounded(), open, 3, Color.pixel(0xF5DF9B))
    }

    private func weatherOnLand(landscape: ForestLandscape) {
        let outline = landOutline(landscape)
        var light = self
        light.context.clip(to: outlinePath(outline))
        light.polygon(outline, color: Color.pixel(0x6B8B9D).opacity(climate.cloudCover * 0.10))
        let drift = sin(time * 0.36) * 20
        light.softEllipse(149 + drift, 133, 105, 48,
                          color: Color.pixel(0xFFF1B1).opacity(climate.sunStrength * 0.26))
        let shadowDrift = sin(time * 0.28) * 38
        light.softEllipse(117 + shadowDrift, 138, 118, 39,
                          color: Color.pixel(0x456A7C).opacity(climate.cloudCover * 0.20))
        if climate.rainIntensity > 0.001 {
            // A damp blue-grey surface ties the shower to the little island.
            // It changes light and reflections only, never growth.
            light.polygon(outline, color: Color.pixel(0x426D83).opacity(climate.rainIntensity * 0.22))
            let width = 314 * landscape.landScale
            let height = 38 + 66 * landscape.expansionProgress
            for index in 0..<(landscape.completedRests < 3 ? 2 : 3) {
                let centerX = 194 + (index == 0 ? -0.24 : index == 1 ? 0.22 : 0.03) * width
                let centerY = 154 + (index == 0 ? -0.06 : index == 1 ? 0.22 : 0.36) * height
                let puddleWidth = 12 + landscape.landScale * 17
                light.softEllipse(centerX - puddleWidth / 2, centerY - 3,
                                  puddleWidth, 8,
                                  color: Color.pixel(0xC2DDE0).opacity(climate.rainIntensity * 0.42))
            }
        }
    }

    private func windWisps() {
        let amount = max(0, climate.windStrength - 0.25)
        guard amount > 0 else { return }
        for index in 0..<3 {
            let phase = (time * (resting ? 0.040 : 0.048) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let x = 43 + phase * 281
            let y = 112 + Double(index * 22)
            let opacity = sin(phase * .pi) * amount * (resting ? 0.52 : 0.70)
            var breeze = Path()
            breeze.move(to: .init(x: x, y: y))
            breeze.addQuadCurve(to: .init(x: x + 35, y: y - 2), control: .init(x: x + 17, y: y - 6))
            context.stroke(breeze, with: .color(Color.pixel(0xD5E5D8).opacity(opacity)),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            var trail = Path()
            trail.move(to: .init(x: x - 11, y: y + 5))
            trail.addQuadCurve(to: .init(x: x + 13, y: y + 3), control: .init(x: x + 1, y: y + 2))
            context.stroke(trail, with: .color(Color.pixel(0xA4C1AF).opacity(opacity * 0.55)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
    }

    private func rain(landscape: ForestLandscape) {
        guard climate.rainIntensity > 0.001 else { return }
        // A layered curtain of thin, tapered silver-blue threads, not scattered
        // chunky grey marks. The two depths share one gentle falling direction.
        let density = resting ? 0.76 : 1.0
        for layer in 0..<2 {
            let count = layer == 0 ? 23 : 13
            let speed = layer == 0 ? 28.0 : 39.0
            let length = layer == 0 ? 8.0 : 12.0
            let opacity = climate.rainIntensity * (layer == 0 ? 0.42 : 0.62) * density
            for index in 0..<count {
                let phase = (stable(index + 510 + layer * 80) + time * speed / 121).truncatingRemainder(dividingBy: 1)
                let y = 78 + phase * 121
                let x = 73 + stable(index + 610 + layer * 80) * 231 + phase * 8
                let edgeFade = min(1, phase * 6, (1 - phase) * 5)
                var drop = Path()
                drop.move(to: .init(x: x, y: y))
                drop.addLine(to: .init(x: x + 0.8, y: y + length))
                context.stroke(drop, with: .linearGradient(
                    Gradient(colors: [.clear, Color.pixel(0x6E9EAF).opacity(opacity * edgeFade),
                                      Color.pixel(0xE1F2EF).opacity(opacity * edgeFade * 0.7)]),
                    startPoint: .init(x: x, y: y), endPoint: .init(x: x + 0.8, y: y + length)),
                    style: StrokeStyle(lineWidth: layer == 0 ? 0.62 : 0.85, lineCap: .round))
            }
        }
        var surface = self
        surface.context.clip(to: outlinePath(landOutline(landscape)))
        let width = 314 * landscape.landScale
        let height = 38 + 66 * landscape.expansionProgress
        for index in 0..<(landscape.completedRests < 3 ? 2 : 3) {
            let phase = (time / 2.5 + Double(index) * 0.41).truncatingRemainder(dividingBy: 1)
            let centerX = 194 + (index == 0 ? -0.24 : index == 1 ? 0.22 : 0.03) * width
            let centerY = 154 + (index == 0 ? -0.06 : index == 1 ? 0.22 : 0.36) * height
            let ringWidth = 5 + phase * (landscape.completedRests < 3 ? 14 : 23)
            let ellipse = Path(ellipseIn: CGRect(x: centerX - ringWidth / 2, y: centerY - ringWidth * 0.14,
                                               width: ringWidth, height: ringWidth * 0.28))
            surface.context.stroke(ellipse,
                                   with: .color(Color.pixel(0xD9EEEA).opacity((1 - phase) * climate.rainIntensity * density * 0.84)),
                                   style: StrokeStyle(lineWidth: 0.7))
            if phase < 0.20 {
                surface.rect(centerX - 0.5, centerY - 2.2 * (1 - phase / 0.20), 1, 2,
                             Color.pixel(0xE7F4E9).opacity(climate.rainIntensity * 0.56 * density))
            }
        }
    }

    private func softEllipse(_ x: Double, _ y: Double, _ width: Double, _ height: Double, color: Color) {
        var glow = context
        glow.translateBy(x: x + width / 2, y: y + height / 2)
        glow.scaleBy(x: width / 2, y: height / 2)
        glow.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                  with: .radialGradient(Gradient(stops: [.init(color: color, location: 0),
                                                        .init(color: color.opacity(0.72), location: 0.5),
                                                        .init(color: .clear, location: 1)]),
                                        center: .zero, startRadius: 0, endRadius: 1))
    }

    private func motes() {
        for index in 0..<11 {
            let x = 62 + stable(index + 220) * 271
            let y = 61 + stable(index + 250) * 107
            let phase = Double(index) * 0.7
            let opacity = 0.1 + max(0, sin(time * 0.34 + phase)) * 0.36
            rect(x.rounded(), (y + sin(time * 0.18 + phase) * 3).rounded(), 1, 2,
                 cream.opacity(opacity))
        }
    }

    private func sparkle(x: Double, y: Double, opacity: Double) {
        rect(x, y - 2, 1, 5, cream.opacity(opacity))
        rect(x - 2, y, 5, 1, cream.opacity(opacity))
    }

    private func stable(_ index: Int) -> Double {
        var value = seed &+ UInt64(index) &* 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value % 10_000) / 10_000
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)),
                     with: .color(color), style: FillStyle(antialiased: false))
    }

    private func oval(_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                      color: Color, step: Double) {
        guard width > 0, height > 0 else { return }
        var row = 0.0
        while row < height {
            let centerY = (row + min(step, height - row) / 2) / height * 2 - 1
            let rowWidth = (sqrt(max(0, 1 - centerY * centerY)) * width / (2 * step)).rounded() * (2 * step)
            rect(x + (width - rowWidth) / 2, y + row, rowWidth, min(step, height - row), color)
            row += step
        }
    }

    private func polygon(_ points: [CGPoint], color: Color) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        context.fill(path, with: .color(color), style: FillStyle(antialiased: false))
    }
}

private extension Color {
    static func pixel(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255,
              green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
