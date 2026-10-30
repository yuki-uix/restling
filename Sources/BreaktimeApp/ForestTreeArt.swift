import SwiftUI
import PomodoroCore

/// The new species share these exact shapes in the catalogue, picker and forest.
/// Coordinates are rooted at (0, 0) inside a 72 × 92 design space; the caller
/// supplies soil or shadow. Existing species keep their original painters.
struct ForestTreeIllustration: View {
    let species: ForestSpecies
    let stage: Int

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 72, size.height / 92)
            var tree = context
            tree.translateBy(x: size.width / 2, y: (size.height - 92 * scale) / 2 + 82 * scale)
            tree.scaleBy(x: scale, y: scale)
            ForestNewTreePainter(context: tree).paint(species: species, stage: stage)
        }.accessibilityHidden(true)
    }
}

struct ForestNewTreePainter {
    var context: GraphicsContext
    var canopySway: Double = 0

    func paint(species: ForestSpecies, stage: Int) {
        guard (1...3).contains(stage) else { return }
        switch species {
        case .birch: birch(stage)
        case .willow: willow(stage)
        case .ginkgo: ginkgo(stage)
        case .oak, .pine, .blossom: break
        }
    }

    private func birch(_ stage: Int) {
        let dark = color(0x667F60), leaf = color(0x8EAD70), light = color(0xBDCE91)
        let bark = color(0x9A9F89), white = color(0xEEE7CE), mark = color(0x798374)
        if stage == 1 {
            rect(-1, -13, 2, 13, white)
            rect(-1, -5, 1, 2, mark)
            var crown = self; crown.context.translateBy(x: canopySway * 0.4, y: 0)
            crown.oval(-8, -16, 8, 5, leaf, step: 1)
            crown.oval(0, -21, 6, 9, leaf, step: 1)
            crown.rect(1, -20, 2, 5, light)
            return
        }
        if stage == 2 {
            rect(-2, -30, 4, 30, bark)
            rect(-1, -30, 2, 30, white)
            rect(-7, -31, 6, 2, white); rect(1, -35, 6, 2, white)
            rect(-1, -9, 2, 2, mark); rect(-2, -20, 2, 2, mark)
            var crown = self; crown.context.translateBy(x: canopySway * 0.6, y: 0)
            crown.oval(-14, -45, 13, 20, dark, step: 2)
            crown.oval(-12, -46, 11, 16, leaf, step: 2)
            crown.oval(0, -51, 14, 23, leaf, step: 2)
            crown.oval(2, -51, 8, 12, light, step: 2)
            return
        }
        rect(-3, -54, 6, 54, bark); rect(-2, -54, 4, 54, white)
        rect(-11, -51, 9, 3, white); rect(2, -57, 11, 3, white)
        rect(-8, -56, 3, 8, white); rect(10, -63, 3, 9, white)
        rect(-3, -10, 3, 2, mark); rect(0, -19, 3, 2, mark)
        rect(-3, -30, 4, 2, mark); rect(0, -42, 3, 3, mark)
        rect(-5, -2, 10, 2, bark)
        var crown = self; crown.context.translateBy(x: canopySway, y: 0)
        crown.oval(-23, -75, 22, 35, dark, step: 3)
        crown.oval(-20, -77, 18, 29, leaf, step: 3)
        crown.oval(-4, -82, 22, 39, dark, step: 3)
        crown.oval(-3, -82, 18, 32, leaf, step: 3)
        crown.oval(11, -68, 17, 29, leaf, step: 3)
        crown.oval(-16, -75, 10, 17, light, step: 2)
        crown.oval(1, -80, 9, 18, light, step: 2)
        crown.rect(-11, -53, 4, 3, color(0xD6DBA7))
        crown.rect(17, -58, 4, 3, light)
    }

    private func willow(_ stage: Int) {
        let bark = color(0x7C7953), dark = color(0x567C54), mid = color(0x83A66B)
        let light = color(0xB0C585)
        if stage == 1 {
            rect(-1, -13, 2, 13, bark)
            var crown = self; crown.context.translateBy(x: canopySway * 0.4, y: 0)
            crown.rect(-5, -15, 4, 3, mid); crown.rect(-7, -13, 3, 8, mid)
            crown.rect(-7, -6, 2, 3, light)
            crown.rect(1, -18, 5, 3, mid); crown.rect(5, -16, 3, 10, mid)
            crown.rect(6, -7, 2, 3, light)
            return
        }
        if stage == 2 {
            rect(-2, -27, 4, 27, bark); rect(-1, -24, 2, 24, color(0xA29A65))
            rect(-8, -28, 7, 3, bark); rect(1, -31, 8, 3, bark)
            var crown = self; crown.context.translateBy(x: canopySway * 0.65, y: 0)
            crown.oval(-18, -44, 36, 17, dark, step: 2)
            crown.oval(-16, -45, 31, 13, mid, step: 2)
            for (index, x) in [-16.0, -11, -6, 5, 10, 15].enumerated() {
                let top = -37.0 + Double(index % 2) * 3
                crown.rect(x, top, 3, 19 - Double(index % 3) * 2, mid)
                crown.rect(x, top + 14, 2, 5, light)
            }
            crown.rect(-8, -42, 9, 3, light)
            return
        }
        rect(-3, -46, 6, 46, bark); rect(0, -43, 2, 43, color(0xA29A65))
        rect(-12, -43, 10, 3, bark); rect(2, -47, 12, 3, bark)
        rect(-15, -48, 3, 7, bark); rect(12, -51, 3, 7, bark)
        rect(-6, -2, 12, 2, bark)
        var crown = self; crown.context.translateBy(x: canopySway, y: 0)
        crown.oval(-32, -67, 64, 29, dark, step: 3)
        crown.oval(-29, -69, 57, 24, mid, step: 3)
        crown.oval(-21, -68, 39, 14, light, step: 3)
        for (index, x) in [-30.0, -24, -18, -11, -5, 5, 12, 19, 26].enumerated() {
            let top = -53.0 + Double(index % 3) * 3
            let length = 34.0 - Double(index % 4) * 3
            crown.rect(x, top, 4, length, index % 2 == 0 ? dark : mid)
            crown.rect(x + 1, top + 2, 2, length - 3, mid)
            crown.rect(x, top + length - 5, 2, 6, light)
        }
        crown.rect(-15, -63, 11, 3, color(0xCDD69B))
        crown.rect(5, -58, 10, 3, light)
    }

    private func ginkgo(_ stage: Int) {
        let bark = color(0x8C7950), dark = color(0x858C47), mid = color(0xB8B75A)
        let light = color(0xDDD079)
        if stage == 1 {
            rect(-1, -12, 2, 12, bark)
            var crown = self; crown.context.translateBy(x: canopySway * 0.4, y: 0)
            crown.fan(x: 0, y: -11, scale: 0.34, fill: mid, highlight: light)
            crown.rect(-1, -8, 1, 6, dark)
            return
        }
        if stage == 2 {
            rect(-2, -25, 4, 25, bark); rect(0, -23, 1, 23, color(0xAD9562))
            rect(-8, -23, 7, 2, bark); rect(1, -29, 7, 2, bark)
            var crown = self; crown.context.translateBy(x: canopySway * 0.65, y: 0)
            crown.fan(x: -8, y: -24, scale: 0.52, fill: dark, highlight: mid)
            crown.fan(x: 6, y: -28, scale: 0.60, fill: mid, highlight: light)
            return
        }
        rect(-3, -52, 6, 52, bark); rect(0, -49, 2, 49, color(0xAD9562))
        rect(-16, -37, 14, 3, bark); rect(2, -42, 15, 3, bark)
        rect(-19, -43, 3, 9, bark); rect(15, -48, 3, 9, bark)
        rect(-6, -2, 12, 2, bark)
        var crown = self; crown.context.translateBy(x: canopySway, y: 0)
        crown.fan(x: -14, y: -36, scale: 0.88, fill: dark, highlight: mid)
        crown.fan(x: 13, y: -40, scale: 0.92, fill: mid, highlight: light)
        crown.fan(x: 0, y: -53, scale: 1, fill: mid, highlight: color(0xE6D98A))
    }

    /// A notched, radiating fan, rather than a recoloured rounded canopy.
    private func fan(x: Double, y: Double, scale: Double, fill: Color, highlight: Color) {
        var leaf = self
        leaf.context.translateBy(x: x, y: y)
        leaf.context.scaleBy(x: scale, y: scale)
        let points: [CGPoint] = [
            .init(x: 0, y: 0), .init(x: -7, y: -4), .init(x: -14, y: -12),
            .init(x: -17, y: -20), .init(x: -12, y: -26), .init(x: -6, y: -29),
            .init(x: -2, y: -25), .init(x: 0, y: -20), .init(x: 3, y: -26),
            .init(x: 9, y: -29), .init(x: 16, y: -23), .init(x: 19, y: -14),
            .init(x: 12, y: -7), .init(x: 5, y: -3)
        ]
        var path = Path()
        path.addLines(points); path.closeSubpath()
        leaf.context.fill(path, with: .color(fill), style: FillStyle(antialiased: false))
        leaf.rect(-11, -23, 6, 3, highlight)
        leaf.rect(6, -22, 6, 3, highlight)
        leaf.rect(-8, -17, 2, 5, highlight.opacity(0.65))
        leaf.rect(7, -16, 2, 5, highlight.opacity(0.65))
        leaf.rect(-3, -10, 2, 4, highlight.opacity(0.6))
        leaf.rect(2, -9, 2, 4, highlight.opacity(0.6))
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)),
                     with: .color(color), style: FillStyle(antialiased: false))
    }

    private func oval(_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                      _ color: Color, step: Double) {
        var row = 0.0
        while row < height {
            let center = (row + min(step, height - row) / 2) / height * 2 - 1
            let rowWidth = (sqrt(max(0, 1 - center * center)) * width / (2 * step)).rounded() * (2 * step)
            rect(x + (width - rowWidth) / 2, y + row, rowWidth, min(step, height - row), color)
            row += step
        }
    }

    private func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255,
              green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
