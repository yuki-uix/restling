import SwiftUI
import PomodoroCore

/// A read-only collection of the current forest's earned milestones.
/// Selection is presentation state; opening a badge never records an event.
@MainActor
struct ForestAchievementsView: View {
    @ObservedObject private var forest: ForestStore
    private let onClose: () -> Void
    @State private var category: ForestAchievementCategory?
    @State private var selected: ForestAchievement?

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.42, green: 0.49, blue: 0.41)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    init(forest: ForestStore, onClose: @escaping () -> Void) {
        self.forest = forest
        self.onClose = onClose
    }

    private var profile: ForestProfile { forest.current }
    private var collection: ForestAchievements { ForestAchievements(profile: profile) }
    private var visibleItems: [ForestAchievementProgress] {
        category.map { collection.items(in: $0) } ?? collection.items
    }
    private var selectedItem: ForestAchievementProgress? {
        if let selected, let item = visibleItems.first(where: { $0.achievement == selected }) {
            return item
        }
        if let next = collection.nextAchievement,
           visibleItems.contains(where: { $0.id == next.id }) { return next }
        return visibleItems.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let item = selectedItem { detail(item) }
            filters
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          alignment: .leading, spacing: 12) {
                    ForEach(visibleItems) { item in card(item) }
                }
                .padding(.horizontal, 26)
                .padding(.top, 2)
                .padding(.bottom, 18)
            }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("足迹随休息自然留下，无需领取。")
                        .font(.system(size: 11, weight: .medium))
                    Text("中断几天也不会失去。每片森林，珍藏自己的足迹。")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Button("完成", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("achievements.done")
            }
            .padding(.horizontal, 26).padding(.vertical, 15)
        }
        .frame(width: 760, height: 680)
        .background(paper).foregroundStyle(ink).tint(green)
        .preferredColorScheme(.light)
        .onChange(of: profile.id) { _ in category = nil; selected = nil }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("森林足迹").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("\(collection.unlockedCount) / \(collection.totalCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(green.opacity(0.08), in: Capsule())
                        .accessibilityLabel("已留下 \(collection.unlockedCount) 枚，共 \(collection.totalCount) 枚足迹")
                }
                Text("\(profile.name) · 给自己留的片刻，都在这里慢慢积累。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(green.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭森林足迹")
            .accessibilityIdentifier("achievements.close")
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
    }

    private func detail(_ item: ForestAchievementProgress) -> some View {
        HStack(alignment: .center, spacing: 18) {
            ForestAchievementBadge(achievement: item.achievement, isUnlocked: item.isUnlocked)
                .frame(width: 94, height: 94)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.achievement.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Spacer(minLength: 10)
                    status(item)
                }
                Text(item.story)
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text(item.requirement)
                        .font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 0)
                    Text(item.progressText)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }
                ProgressView(value: item.fraction)
                    .accessibilityLabel("\(item.achievement.title)进度")
                    .accessibilityValue(item.progressText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(green.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(green.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("achievements.detail")
    }

    private var filters: some View {
        HStack(spacing: 7) {
            filter("全部", category: nil)
            ForEach(ForestAchievementCategory.allCases) { item in filter(item.title, category: item) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.vertical, 16)
    }

    private func filter(_ title: String, category value: ForestAchievementCategory?) -> some View {
        let active = category == value
        return Button {
            category = value
            selected = nil
        } label: {
            Text(title).font(.system(size: 11, weight: active ? .semibold : .regular))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .foregroundStyle(active ? paper : ink)
                .background(active ? green : green.opacity(0.055), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)足迹")
        .accessibilityValue(active ? "已选择" : "未选择")
        .accessibilityIdentifier("achievements.filter.\(value?.rawValue ?? "all")")
    }

    private func card(_ item: ForestAchievementProgress) -> some View {
        let active = selectedItem?.id == item.id
        return Button {
            selected = item.achievement
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ForestAchievementBadge(achievement: item.achievement, isUnlocked: item.isUnlocked)
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(item.achievement.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                        Spacer(minLength: 0)
                        if item.isUnlocked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(green)
                        }
                    }
                    Text(item.requirement)
                        .font(.system(size: 10)).foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: item.fraction).accessibilityHidden(true)
                    HStack {
                        Text(item.isUnlocked ? "已留下" : "还在路上")
                        Spacer(minLength: 0)
                        Text(item.progressText).monospacedDigit()
                    }.font(.system(size: 9)).foregroundStyle(muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(Color.white.opacity(item.isUnlocked ? 0.75 : 0.45), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .stroke(green.opacity(active ? 0.55 : item.isUnlocked ? 0.14 : 0.07), lineWidth: active ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(item.achievement.title)，\(item.isUnlocked ? "已留下" : "还在路上")，\(item.requirement)")
        .accessibilityValue("\(item.progressText)\(active ? "，已选择" : "")")
        .accessibilityHint("查看足迹故事和达成条件")
        .accessibilityIdentifier("achievement.\(item.achievement.rawValue)")
    }

    private func status(_ item: ForestAchievementProgress) -> some View {
        Label(item.isUnlocked ? "已留下" : "还在路上",
              systemImage: item.isUnlocked ? "checkmark.circle" : "leaf")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(item.isUnlocked ? green : muted)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(green.opacity(0.07), in: Capsule())
    }
}
