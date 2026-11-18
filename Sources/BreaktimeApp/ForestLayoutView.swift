import SwiftUI
import PomodoroCore

/// Changes only the placement of already earned trees in the current week.
/// There is no claiming step, new tree, rest event or timer action here.
@MainActor
struct ForestLayoutView: View {
    @ObservedObject private var forest: ForestStore
    private let onClose: () -> Void
    @State private var selectedTreeID: UUID?
    @State private var selectedPage = 0
    @State private var message: String?

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.42, green: 0.49, blue: 0.41)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    init(forest: ForestStore, onClose: @escaping () -> Void) {
        self.forest = forest
        self.onClose = onClose
    }

    private var profile: ForestProfile { forest.current }
    private var week: ForestWeek? { forest.currentWeek }
    private var trees: [ForestTree] { week.map { profile.trees(inWeekID: $0.id) } ?? [] }
    private var pageCount: Int { week?.pageCount ?? 1 }
    private var page: Int { min(max(0, selectedPage), pageCount - 1) }
    private var selectedTree: ForestTree? { trees.first { $0.id == selectedTreeID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if trees.isEmpty { emptyState }
                    else {
                        ForestSceneView(profile: profile, groveIndex: page, animationEnabled: false,
                                        selection: .currentWeek, displayDate: forest.displayDate)
                            .frame(height: 170)
                            .background(green.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                        collection
                        positionHeader
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
                            ForEach(0..<16, id: \.self) { localSlot in slotButton(page * 16 + localSlot) }
                        }
                    }
                }.padding(.horizontal, 26).padding(.bottom, 18)
            }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message ?? "布置只改变本周成树的位置，修改后立即保存。")
                        .font(.system(size: 11)).foregroundStyle(muted)
                    Text("历史森林、树种与休息记录保留。")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Button("完成", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("layout.done")
            }.padding(.horizontal, 26).padding(.vertical, 16)
        }
        .frame(width: 700, height: 700)
        .background(paper).foregroundStyle(ink).tint(green)
        .preferredColorScheme(.light)
        .onChange(of: profile.id) { _ in resetSelection() }
        .onChange(of: week?.id) { _ in resetSelection() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("布置本周林地").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("先选一棵树，再选位置。已有树的位置可以交换。")
                    .font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(green.opacity(0.07), in: Circle())
            }.buttonStyle(.plain)
                .accessibilityLabel("关闭本周林地布置")
                .accessibilityIdentifier("layout.close")
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForestSceneView(profile: profile, animationEnabled: false, selection: .currentWeek,
                            displayDate: forest.displayDate)
                .frame(height: 270)
            Text("这一周，还没有成熟树可以布置。")
                .font(.system(size: 16, weight: .medium, design: .rounded))
            Text("每次完整休息都会滋养正在培育的植物。成树会自动留在本周森林，无需领取；想换个位置时再回来。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 20)
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本周长成的树 · \(trees.count) 棵")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(selectedTree.map { "已选：\($0.species.title)" } ?? "选择一棵树")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(trees.enumerated()), id: \.element.id) { index, tree in
                        Button {
                            selectedTreeID = tree.id
                            selectedPage = (week?.slot(for: tree.id) ?? 0) / 16
                            message = nil
                        } label: {
                            HStack(spacing: 7) {
                                ForestLayoutTreeMark(species: tree.species).frame(width: 25, height: 31)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tree.species.title).font(.system(size: 11, weight: .medium))
                                    Text("第 \(index + 1) 棵").font(.system(size: 10)).foregroundStyle(muted)
                                }
                            }.padding(.horizontal, 10).padding(.vertical, 7)
                                .background(green.opacity(selectedTreeID == tree.id ? 0.12 : 0.045),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(green.opacity(selectedTreeID == tree.id ? 0.5 : 0.08), lineWidth: 1))
                                .accessibilityElement(children: .ignore)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("选择本周第 \(index + 1) 棵\(tree.species.title)")
                            .accessibilityValue(selectedTreeID == tree.id ? "已选择" : "未选择")
                            .accessibilityIdentifier("layout.tree.\(index)")
                    }
                }.padding(.bottom, 3)
            }
        }
    }

    private var positionHeader: some View {
        HStack(spacing: 12) {
            Text("位置图 · \(selectedTree == nil ? "选树后可移动" : "点击位置进行移动或交换")")
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
            if pageCount > 1 {
                Button { selectedPage = max(0, page - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22)
                }.disabled(page == 0).accessibilityLabel("上一块布置区域")
                Text("\(page + 1) / \(pageCount)").font(.system(size: 11)).monospacedDigit()
                Button { selectedPage = min(pageCount - 1, page + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 22, height: 22)
                }.disabled(page + 1 >= pageCount).accessibilityLabel("下一块布置区域")
            }
        }.buttonStyle(.plain)
    }

    private func slotButton(_ slot: Int) -> some View {
        let occupant = trees.first { week?.slot(for: $0.id) == slot }
        let isSelected = occupant?.id == selectedTreeID && occupant != nil
        return Button {
            guard let selectedTree else {
                if let occupant { selectedTreeID = occupant.id; message = nil }
                return
            }
            if occupant?.id == selectedTree.id {
                selectedTreeID = nil
                message = nil
            } else if forest.moveTree(id: selectedTree.id, to: slot) {
                message = occupant == nil ? "已移动到位置 \(slot + 1)。" : "已交换两棵树的位置。"
            } else {
                message = "位置没有更改。请确认当前仍是本周林地。"
            }
        } label: {
            HStack(spacing: 7) {
                if let occupant {
                    ForestLayoutTreeMark(species: occupant.species).frame(width: 24, height: 31)
                } else {
                    Image(systemName: "plus").font(.system(size: 13, weight: .light))
                        .frame(width: 24, height: 31).foregroundStyle(muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("位置 \(slot + 1)").font(.system(size: 10, weight: .medium))
                    Text(occupant?.species.title ?? "空地")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(isSelected ? green.opacity(0.13) : Color.white.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(green.opacity(isSelected ? 0.55 : 0.1), lineWidth: 1))
                .accessibilityElement(children: .ignore)
        }.buttonStyle(.plain)
            .disabled(occupant == nil && selectedTree == nil)
            .accessibilityLabel("位置 \(slot + 1)，\(occupant?.species.title ?? "空地")")
            .accessibilityValue(isSelected ? "当前选中的树" : "")
            .accessibilityHint(selectedTree == nil ? "选择这棵树" : occupant == nil ? "将选中的树移到这里" : "与选中的树交换位置")
            .accessibilityIdentifier("layout.slot.\(slot)")
    }

    private func resetSelection() {
        selectedTreeID = nil
        selectedPage = 0
        message = nil
    }
}

/// Compact block sprites reuse the catalogue's new-species painter.
private struct ForestLayoutTreeMark: View {
    let species: ForestSpecies

    @ViewBuilder
    var body: some View {
        if [.birch, .willow, .ginkgo].contains(species) {
            ForestTreeIllustration(species: species, stage: 3).accessibilityHidden(true)
        } else {
            Canvas { context, size in
                let scale = min(size.width / 16, size.height / 18)
                let origin = CGPoint(x: (size.width - 16 * scale) / 2, y: (size.height - 18 * scale) / 2)
                func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                    context.fill(Path(CGRect(x: origin.x + x * scale, y: origin.y + y * scale,
                                             width: width * scale, height: height * scale)), with: .color(color))
                }
                block(7, 11, 2, 6, Color(red: 0.48, green: 0.34, blue: 0.23))
                switch species {
                case .oak:
                    let leaf = Color(red: 0.32, green: 0.53, blue: 0.32)
                    block(3, 3, 10, 9, leaf); block(1, 6, 14, 6, leaf); block(5, 1, 6, 12, leaf)
                    block(4, 4, 4, 3, Color(red: 0.55, green: 0.68, blue: 0.38))
                case .pine:
                    let leaf = Color(red: 0.23, green: 0.48, blue: 0.37)
                    block(7, 0, 2, 3, leaf); block(5, 3, 6, 3, leaf)
                    block(3, 6, 10, 4, leaf); block(1, 10, 14, 4, leaf)
                case .blossom:
                    let leaf = Color(red: 0.85, green: 0.56, blue: 0.61)
                    block(4, 2, 8, 11, leaf); block(1, 5, 14, 6, leaf)
                    block(3, 4, 10, 5, Color(red: 0.95, green: 0.72, blue: 0.72))
                    block(5, 2, 5, 2, Color(red: 0.99, green: 0.83, blue: 0.77))
                case .birch, .willow, .ginkgo: break
                }
            }.accessibilityHidden(true)
        }
    }
}
