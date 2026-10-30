import AppKit
import SwiftUI
import PomodoroCore

/// A quiet map of earned scenery. Browsing and visiting never change growth.
@MainActor
struct ForestEcologyView: View {
    @ObservedObject private var forest: ForestStore
    private let onViewGrove: (Int) -> Void
    private let onClose: () -> Void

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.46, green: 0.52, blue: 0.43)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    init(forest: ForestStore, onViewGrove: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.forest = forest
        self.onViewGrove = onViewGrove
        self.onClose = onClose
    }

    private var profile: ForestProfile { forest.current }
    private var ecology: ForestEcology { ForestEcology(profile: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    progressSummary
                    ForEach(ForestEcologyMilestone.allCases) { milestone in
                        milestoneCard(milestone)
                    }
                    Text("风景按累计休息自然出现。休息时先看看远处，结束后再回来慢慢逛；这里没有需要签到或领取的任务。")
                        .font(.system(size: 11)).foregroundStyle(muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
            }
            Divider()
            HStack {
                Text("已经出现的风景，会留在原来的林地。")
                    .font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                Button("完成", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ecology.done")
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
        .frame(width: 700, height: 650)
        .background(paper)
        .foregroundStyle(ink)
        .tint(green)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("林地手记")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("\(profile.name) · 累计完成 \(profile.completedRests) 次休息")
                    .font(.system(size: 12)).foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(green.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭林地手记")
            .accessibilityIdentifier("ecology.close")
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let next = ecology.nextMilestone {
                HStack(alignment: .firstTextBaseline) {
                    Text("下一处风景 · \(next.title)")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(profile.completedRests) / \(next.unlockAfter) 次")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                }
                ProgressView(value: Double(profile.completedRests), total: Double(next.unlockAfter))
                    .tint(green)
                    .accessibilityLabel("距下一处生态风景的累计进度")
                Text(ecology.nextMilestoneText)
                    .font(.system(size: 11)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("三处新风景，都来到森林了", systemImage: "leaf.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("继续休息，新树和新林地仍会慢慢生长。想念哪处风景，随时回去看看。")
                    .font(.system(size: 11)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(green.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ecology.progress")
    }

    private func milestoneCard(_ milestone: ForestEcologyMilestone) -> some View {
        let unlocked = ecology.isUnlocked(milestone)
        return HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol(for: milestone))
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(green.opacity(unlocked ? 1 : 0.60))
                .frame(width: 62, height: 66)
                .background(green.opacity(unlocked ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(milestone.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Label(unlocked ? "已经出现" : "还在路上", systemImage: unlocked ? "checkmark.circle" : "lock")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Text("累计完成 \(milestone.unlockAfter) 次休息 · 第 \(milestone.groveIndex + 1) 片林地")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
                Text(unlocked ? milestone.detail : milestone.teaser)
                    .font(.system(size: 12)).foregroundStyle(muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if unlocked {
                    Button("去第 \(milestone.groveIndex + 1) 片林地看看") {
                        guard ecology.isUnlocked(milestone),
                              milestone.groveIndex <= ForestLandscape(profile: profile).currentGroveIndex else { return }
                        onViewGrove(milestone.groveIndex)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityIdentifier("ecology.visit.\(milestone.rawValue)")
                } else {
                    Text("再完成 \(max(0, milestone.unlockAfter - profile.completedRests)) 次休息")
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(green.opacity(unlocked ? 0.20 : 0.09), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ecology.milestone.\(milestone.rawValue)")
    }

    private func symbol(for milestone: ForestEcologyMilestone) -> String {
        let candidates: [String]
        switch milestone {
        case .pond: candidates = ["water.waves", "drop"]
        case .bridge: candidates = ["bridge", "point.topleft.down.to.point.bottomright.curvepath"]
        case .visitors: candidates = ["hare.fill", "pawprint.fill"]
        }
        return candidates.first(where: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) ?? "leaf"
    }
}
