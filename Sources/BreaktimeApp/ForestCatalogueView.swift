import SwiftUI
import PomodoroCore

@MainActor
struct ForestCatalogueView: View {
    @ObservedObject var forest: ForestStore
    let onClose: () -> Void
    @State private var selected: ForestSpecies
    @State private var confirmation: String?

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.46, green: 0.52, blue: 0.43)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    init(forest: ForestStore, initiallySelected: ForestSpecies = .oak, onClose: @escaping () -> Void) {
        self.forest = forest
        self.onClose = onClose
        _selected = State(initialValue: initiallySelected)
    }

    private var profile: ForestProfile { forest.current }
    private var unlocked: Bool { profile.isUnlocked(selected) }
    private var isCurrent: Bool { profile.selectedSpecies == selected }
    private var restsToUnlock: Int { max(0, selected.unlockAfter - profile.completedRests) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(spacing: 10) {
                ForEach(ForestSpecies.allCases) { species in speciesTab(species) }
            }.frame(height: 76)

            HStack(alignment: .top, spacing: 22) {
                portrait
                details
            }.frame(height: 348)

            Spacer(minLength: 0)
            Divider().overlay(green.opacity(0.06))
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("改种会保留本轮成长进度。")
                        .font(.system(size: 11, weight: .medium))
                    Text("只影响正在培育的这棵，已长成的树木保持原样。")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Button(action: chooseSpecies) {
                    Label(actionTitle, systemImage: !unlocked ? "lock.fill" : isCurrent ? "checkmark" : "leaf")
                        .font(.system(size: 12, weight: .medium)).padding(.vertical, 3)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!unlocked || isCurrent)
                    .accessibilityLabel(actionTitle)
            }.frame(height: 52)
        }
        .padding(26)
        .frame(width: 740, height: 650)
        .background(paper).foregroundStyle(ink).tint(green)
        .preferredColorScheme(.light)
        .onChange(of: profile.id) { _ in confirmation = nil }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("树种图鉴").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("先看看它们的样子，再慢慢把它们种进森林。")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(green.opacity(0.07), in: Circle())
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭树种图鉴").help("关闭树种图鉴（Esc）")
        }.frame(height: 48)
    }

    private func speciesTab(_ species: ForestSpecies) -> some View {
        let canPlant = profile.isUnlocked(species)
        let browsing = selected == species
        return Button {
            selected = species
            confirmation = nil
        } label: {
            HStack(spacing: 9) {
                CatalogueTreeIllustration(species: species, stage: 3)
                    .frame(width: 47, height: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(species.title).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 3) {
                        if !canPlant { Image(systemName: "lock.fill").font(.system(size: 8)) }
                        Text(canPlant ? (species == profile.selectedSpecies ? "正在培育" : "已解锁 · 可选择") : "休息 \(species.unlockAfter) 次解锁")
                            .font(.system(size: 9)).foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 1)
            }.padding(.horizontal, 11).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(browsing ? green.opacity(0.09) : Color.white.opacity(0.50),
                            in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .stroke(browsing ? green.opacity(0.45) : green.opacity(0.10), lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityLabel("查看\(species.title)图鉴，\(canPlant ? "已解锁" : "休息 \(species.unlockAfter) 次解锁")")
    }

    private var portrait: some View {
        VStack(spacing: 9) {
            CatalogueTreeIllustration(species: selected, stage: 3)
                .frame(maxWidth: .infinity).frame(height: 276)
            Text("成树外观").font(.system(size: 11, weight: .medium))
            Text("外观示意 · 不计入你的森林")
                .font(.system(size: 9)).foregroundStyle(muted)
        }.padding(14).frame(width: 218, height: 348)
            .background(green.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(green.opacity(0.09), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(selected.title)成树外观示意，不计入森林进度")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(selected.title).font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Label(unlocked ? "已解锁" : "还在路上", systemImage: unlocked ? "checkmark.circle" : "lock")
                    .font(.system(size: 10)).foregroundStyle(muted)
            }
            Text(description).font(.system(size: 12)).foregroundStyle(muted)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("每轮三次休息，会这样慢慢长大").font(.system(size: 11, weight: .semibold))
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { stage in
                        VStack(spacing: 5) {
                            CatalogueTreeIllustration(species: selected, stage: stage)
                                .frame(height: 84)
                            Text(["新芽", "幼苗", "成树"][stage - 1])
                                .font(.system(size: 10, weight: .medium))
                            Text("本轮第 \(stage) 次休息")
                                .font(.system(size: 9)).foregroundStyle(muted)
                        }.padding(.vertical, 7).frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(green).font(.system(size: 11, weight: .medium))
                } else if !unlocked {
                    Text("再完成 \(restsToUnlock) 次休息，就能选择\(selected.title)。")
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Text(isCurrent ? "正在培育\(selected.title) · 本轮 \(profile.growthStage) / 3" : "可以选择\(selected.title)，本轮成长进度会保留。")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(!unlocked ? "现在就可以自由查看外观，预览不会提前解锁。" : "还需 \(profile.restsUntilTree) 次完整休息，这棵树就会留在林间。")
                    .font(.system(size: 10)).foregroundStyle(muted)
            }.padding(.top, 1)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var actionTitle: String {
        if !unlocked { return "再休息 \(restsToUnlock) 次解锁" }
        return isCurrent ? "正在培育\(selected.title)" : "选择\(selected.title)"
    }

    private var description: String {
        switch selected {
        case .oak: return "圆圆的树冠，浅绿里藏着一点阳光。它是这片森林最初的陪伴。"
        case .pine: return "层层针叶，长成一座小小的绿色尖塔。让林间多一点清凉的深绿。"
        case .blossom: return "柔粉的花冠，像一团轻轻落在枝头的云。给自己的森林留一点春天。"
        }
    }

    private func chooseSpecies() {
        guard unlocked, !isCurrent else { return }
        forest.selectSpecies(selected)
        if forest.current.selectedSpecies == selected {
            confirmation = "已选择\(selected.title)，成长进度保留。"
        }
    }
}

/// Uses the same original block shapes and palette as the forest renderer.
/// These illustrations are independent of profile data and never grant progress.
private struct CatalogueTreeIllustration: View {
    let species: ForestSpecies
    let stage: Int

    var body: some View {
        Canvas { context, size in
            var painter = CatalogueTreePainter(context: context)
            let scale = min(size.width / 72, size.height / 92)
            painter.context.translateBy(x: size.width / 2, y: (size.height - 92 * scale) / 2 + 82 * scale)
            painter.context.scaleBy(x: scale, y: scale)
            painter.paint(species: species, stage: stage)
        }.accessibilityHidden(true)
    }
}

private struct CatalogueTreePainter {
    var context: GraphicsContext

    func paint(species: ForestSpecies, stage: Int) {
        oval(-22, -3, 44, 9, color: color(0x526D4C).opacity(0.12), step: 2)
        oval(-17, -2, 34, 7, color: color(0xB49A6E).opacity(0.45), step: 2)
        oval(-13, -1, 26, 5, color: color(0x947750), step: 1)
        if stage == 1 {
            rect(-1, -12, 2, 12, color(0x608050))
            rect(-6, -15, 6, 4, color(0x7DA862))
            rect(-9, -16, 5, 2, color(0xAAC47B))
            rect(1, -18, 6, 4, color(0x699C54))
            rect(5, -19, 4, 2, color(0xB2CD86))
        } else {
            var tree = self
            if stage == 2 { tree.context.scaleBy(x: 0.58, y: 0.58) }
            tree.rect(-3, -29, 6, 30, color(0x755845))
            tree.rect(0, -27, 2, 26, color(0xA47D51))
            tree.rect(-6, -2, 11, 3, color(0x755845))
            tree.rect(-5, -22, 3, 6, color(0x755845))
            tree.rect(3, -27, 5, 3, color(0x755845))
            switch species {
            case .oak: tree.oak()
            case .pine: tree.pine()
            case .blossom: tree.blossom()
            }
        }
    }

    private func oak() {
        oval(-25, -63, 49, 43, color: color(0x3C6C4E), step: 5)
        oval(-29, -52, 22, 25, color: color(0x3C6C4E), step: 4)
        oval(10, -52, 20, 24, color: color(0x3C6C4E), step: 4)
        oval(-22, -65, 42, 33, color: color(0x6C995B), step: 4)
        oval(-24, -54, 24, 22, color: color(0x6C995B), step: 4)
        oval(1, -58, 23, 23, color: color(0x7DA667), step: 4)
        oval(-15, -65, 28, 19, color: color(0x94B976), step: 4)
        rect(-13, -61, 9, 4, color(0xB7CD83))
        rect(-19, -52, 6, 3, color(0xA9C17B))
        rect(7, -52, 6, 3, color(0xA9C17B))
        rect(-6, -35, 6, 3, color(0x558150))
        rect(13, -39, 4, 3, color(0x9AB56D))
    }

    private func pine() {
        let shadow = color(0x345E4D), mid = color(0x58896A), bright = color(0x81A67A)
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

    private func blossom() {
        oval(-25, -61, 50, 39, color: color(0xAD7B84), step: 4)
        oval(-28, -53, 24, 24, color: color(0xBD8C93), step: 4)
        oval(-22, -64, 43, 34, color: color(0xD9A6A7), step: 4)
        oval(1, -58, 24, 24, color: color(0xE7BAB5), step: 4)
        oval(-14, -64, 26, 19, color: color(0xF0CDC0), step: 4)
        rect(-15, -57, 5, 3, color(0xFAE2CA))
        rect(7, -50, 5, 3, color(0xFAE2CA))
        rect(-4, -40, 4, 3, color(0xF0CDC0))
        rect(12, -32, 3, 3, color(0xD9A6A7))
    }

    private func steppedPine(top: Double, width: Double, height: Double, color: Color) {
        let rows = Int(height / 4)
        for index in 0..<rows {
            let rowWidth = max(4, (width * Double(index + 1) / Double(rows) / 2).rounded() * 2)
            rect(-rowWidth / 2, top + Double(index) * 4, rowWidth, 4, color)
        }
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)),
                     with: .color(color), style: FillStyle(antialiased: false))
    }

    private func oval(_ x: Double, _ y: Double, _ width: Double, _ height: Double, color: Color, step: Double) {
        var row = 0.0
        while row < height {
            let centerY = (row + min(step, height - row) / 2) / height * 2 - 1
            let rowWidth = (sqrt(max(0, 1 - centerY * centerY)) * width / (2 * step)).rounded() * (2 * step)
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
