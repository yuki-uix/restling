import SwiftUI
import PomodoroCore

/// A viewing choice only. Opening a dated forest never advances growth.
enum ForestYearbookSelection: Hashable, Identifiable {
    case currentWeek
    case week(String)
    case legacyGrove(Int)

    var id: String {
        switch self {
        case .currentWeek: return "currentWeek"
        case .week(let id): return "week." + id
        case .legacyGrove(let index): return "legacy.\(index)"
        }
    }
}

@MainActor
struct ForestYearbookView: View {
    @ObservedObject private var forest: ForestStore
    private let onVisit: (ForestYearbookSelection) -> Void
    private let onClose: () -> Void
    @State private var selected: ForestYearbookSelection?
    @State private var detailPage = 0

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.42, green: 0.49, blue: 0.41)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    init(forest: ForestStore, onVisit: @escaping (ForestYearbookSelection) -> Void,
         onClose: @escaping () -> Void) {
        self.forest = forest
        self.onVisit = onVisit
        self.onClose = onClose
    }

    private var profile: ForestProfile { forest.current }
    private var journey: ForestWeeklyJourney? { profile.weeklyJourney }
    private var weeks: [ForestWeek] { journey?.weeks.sorted { $0.id > $1.id } ?? [] }
    private var months: [String] { Set(weeks.map(\.monthID)).sorted(by: >) }
    private var currentWeek: ForestWeek? { forest.currentWeek }
    private var legacyRests: Int { journey?.legacyCompletedRests ?? profile.completedRests }
    private var legacySeconds: TimeInterval { journey?.legacyRestSeconds ?? profile.totalRestSeconds }
    private var legacyTreeCount: Int { journey?.legacyTreeCount ?? profile.trees.count }
    private var hasLegacy: Bool { legacyRests > 0 || legacyTreeCount > 0 }
    private var legacyGroveCount: Int { ForestLandscape(completedRests: legacyRests).groveCount }
    private var selectedWeek: ForestWeek? {
        switch selected {
        case .currentWeek: return currentWeek
        case .week(let id): return weeks.first { $0.id == id }
        default: return nil
        }
    }
    private var isLegacyDetail: Bool {
        if case .legacyGrove = selected { return true }
        return false
    }
    private var selectedPageCount: Int {
        ForestScenePresentation(profile: profile, selection: selected ?? .currentWeek,
                                date: forest.displayDate).pageCount
    }
    private var page: Int { min(max(0, detailPage), selectedPageCount - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if selected == nil { overview }
                    else { details }
                }
                .padding(.horizontal, 26).padding(.bottom, 20)
            }
            Divider()
            footer
        }
        .frame(width: 820, height: 700)
        .background(paper).foregroundStyle(ink).tint(green)
        .preferredColorScheme(.light)
        .onChange(of: profile.id) { _ in selected = nil; detailPage = 0 }
        .onChange(of: selected) { value in
            if case .legacyGrove(let index) = value { detailPage = index }
            else { detailPage = 0 }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("森林年鉴").font(.system(size: 23, weight: .semibold, design: .rounded))
                    if selected != nil {
                        Button { selected = nil } label: {
                            Label("全部森林", systemImage: "chevron.left")
                                .font(.system(size: 11, weight: .medium))
                        }.buttonStyle(.link).accessibilityIdentifier("yearbook.back")
                    }
                }
                Text("\(profile.name) · 留下了 \(weeks.count) 片有休息记录的周森林")
                    .font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(green.opacity(0.07), in: Circle())
            }.buttonStyle(.plain)
                .accessibilityLabel("关闭森林年鉴")
                .accessibilityIdentifier("yearbook.close")
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
    }

    @ViewBuilder
    private var overview: some View {
        if let week = currentWeek, week.isEmpty {
            Button { selected = .currentWeek } label: {
                HStack(spacing: 12) {
                    Image(systemName: "leaf").font(.system(size: 22, weight: .light))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("本周森林 · 等待第一点养分").font(.system(size: 13, weight: .semibold))
                        Text(ForestYearbookFormatting.range(week) + " · 完成休息后，才会留下这一周的记录。")
                            .font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11))
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(green.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .ignore)
            }.buttonStyle(.plain)
                .accessibilityLabel("查看本周空地，\(ForestYearbookFormatting.range(week))，尚无完成休息记录")
                .accessibilityIdentifier("yearbook.current")
        }
        ForEach(months, id: \.self) { month in
            VStack(alignment: .leading, spacing: 12) {
                Text(ForestYearbookFormatting.month(month))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                          alignment: .leading, spacing: 14) {
                    ForEach(weeks.filter { $0.monthID == month }) { week in weekCard(week) }
                }
            }
        }
        if hasLegacy {
            VStack(alignment: .leading, spacing: 12) {
                Text("最初的森林").font(.system(size: 15, weight: .semibold, design: .rounded))
                legacyCard
            }
        }
        if weeks.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("每一周，都有自己的样子。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text("从现在起，有完成休息的周会留在这里。没有使用的周不补造，只有幼苗、还没有成树的一周也会被记住。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 10)
        }
    }

    private func weekCard(_ week: ForestWeek) -> some View {
        let isCurrent = currentWeek?.id == week.id
        return Button { selected = isCurrent ? .currentWeek : .week(week.id) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ForestSceneView(profile: profile, groveIndex: 0, animationEnabled: false, selection: .week(week.id),
                                displayDate: forest.displayDate)
                    .frame(height: 154)
                    .background(green.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                HStack {
                    Text(ForestYearbookFormatting.range(week))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer(minLength: 4)
                    if isCurrent {
                        Text("本周").font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(green.opacity(0.09), in: Capsule())
                    }
                }
                Text("\(week.completedRests) 次休息 · \(ForestYearbookFormatting.duration(week.totalRestSeconds)) · \(week.treeCount) 棵成树")
                    .font(.system(size: 10)).foregroundStyle(muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(green.opacity(0.1), lineWidth: 1))
            .accessibilityElement(children: .ignore)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(ForestYearbookFormatting.range(week, includeYear: true))，\(week.completedRests) 次休息，\(ForestYearbookFormatting.duration(week.totalRestSeconds))，\(week.treeCount) 棵成熟树\(isCurrent ? "，本周" : "")")
            .accessibilityHint("查看这一周的完整森林与记录")
            .accessibilityIdentifier("yearbook.week.\(week.id)")
    }

    private var legacyCard: some View {
        Button { selected = .legacyGrove(0) } label: {
            HStack(spacing: 18) {
                ForestSceneView(profile: profile, animationEnabled: false, selection: .legacyGrove(0),
                                displayDate: forest.displayDate)
                    .frame(width: 224, height: 126).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("最初的森林").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("\(legacyRests) 次休息 · \(ForestYearbookFormatting.duration(legacySeconds)) · \(legacyTreeCount) 棵成树")
                        .font(.system(size: 11)).foregroundStyle(muted)
                    Text("升级前的森林完整保留。旧累计没有分周日期，不会被拆成新的周记录。")
                        .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(green.opacity(0.1), lineWidth: 1))
                .accessibilityElement(children: .ignore)
        }.buttonStyle(.plain)
            .accessibilityLabel("查看最初的森林，\(legacyRests) 次休息，\(legacyTreeCount) 棵树，旧林地与布局保留")
            .accessibilityIdentifier("yearbook.legacy")
    }

    @ViewBuilder
    private var details: some View {
        if isLegacyDetail {
            detailHeading("最初的森林", subtitle: "旧进度完整保留 · 未推造分周日期")
            scene(selection: .legacyGrove(page))
            statistics(rests: legacyRests, seconds: legacySeconds, trees: legacyTreeCount)
            treeTypes(profile.legacyTrees)
            Text("这片森林保留升级前的树木、原有林地与风景。后续完成的休息会进入本周森林。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        } else if let week = selectedWeek {
            detailHeading(currentWeek?.id == week.id ? "本周森林" : "这一周的森林",
                          subtitle: ForestYearbookFormatting.range(week, includeYear: true))
            scene(selection: selected ?? .currentWeek)
            statistics(rests: week.completedRests, seconds: week.totalRestSeconds, trees: week.treeCount)
            treeTypes(profile.trees(inWeekID: week.id))
            if week.isEmpty {
                Text("这里还没有本周的休息记录。完成第一次休息后，年鉴才会收录这一周。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
            } else if week.lastGrowthCount > 0 {
                Text("这一周留下 \(week.lastGrowthCount) / \(week.lastGrowthTarget) 次滋养进度。未成熟的植物会跨周继续培育，成树留在成熟的那一周。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("成树留在这一周。每次休息的记录都已保存，下一株植物会继续慢慢生长。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("这片森林已不在当前档案中。")
                .font(.system(size: 14, weight: .medium))
            Button("返回全部森林") { selected = nil }.buttonStyle(.link)
        }
    }

    private func detailHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(muted)
        }
    }

    private func scene(selection: ForestYearbookSelection) -> some View {
        VStack(spacing: 8) {
            ForestSceneView(profile: profile, groveIndex: page, animationEnabled: false,
                            selection: selection, displayDate: forest.displayDate)
                .frame(height: 240)
                .background(green.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            if selectedPageCount > 1 {
                HStack(spacing: 12) {
                    Button { detailPage = max(0, page - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 22, height: 22)
                    }.disabled(page == 0).accessibilityLabel("查看上一块林地")
                    Text("第 \(page + 1) 块 / 共 \(selectedPageCount) 块")
                        .font(.system(size: 11)).foregroundStyle(muted)
                    Button { detailPage = min(selectedPageCount - 1, page + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 22, height: 22)
                    }.disabled(page + 1 >= selectedPageCount).accessibilityLabel("查看下一块林地")
                }.buttonStyle(.plain)
            }
        }
    }

    private func statistics(rests: Int, seconds: TimeInterval, trees: Int) -> some View {
        HStack(spacing: 30) {
            statistic("完成休息", value: "\(rests) 次")
            statistic("休息计时时长", value: ForestYearbookFormatting.duration(seconds))
            statistic("长成的树", value: "\(trees) 棵")
            Spacer(minLength: 0)
        }.padding(.vertical, 2)
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(muted)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }

    private func treeTypes(_ trees: [ForestTree]) -> some View {
        let names = ForestSpecies.allCases.filter { species in trees.contains { $0.species == species } }.map(\.title)
        return Text(names.isEmpty ? "还没有成熟树，休息的养分已经留下。" : "这里长成过：" + names.joined(separator: "、"))
            .font(.system(size: 12)).foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("没有使用的周不补造，也不要求连续。")
                .font(.system(size: 11)).foregroundStyle(muted)
            Spacer(minLength: 0)
            Button("完成", action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("yearbook.done")
            if let selected, isLegacyDetail || selectedWeek != nil {
                Button("在主界面查看") {
                    if isLegacyDetail { onVisit(.legacyGrove(page)) }
                    else { onVisit(selected) }
                }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("yearbook.visit")
            }
        }.padding(.horizontal, 26).padding(.vertical, 16)
    }
}

enum ForestYearbookFormatting {
    static func range(_ week: ForestWeek, includeYear: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: week.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = includeYear ? "yyyy年M月d日" : "M月d日"
        let start = formatter.string(from: week.startDate)
        formatter.dateFormat = "M月d日"
        return start + "—" + formatter.string(from: week.endDate.addingTimeInterval(-1))
    }

    static func month(_ id: String) -> String {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return id }
        return "\(year) 年 · \(month) 月"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds <= 86_400_000_000 else { return "—" }
        let whole = Int(seconds.rounded(.down))
        let hours = whole / 3_600
        let minutes = whole % 3_600 / 60
        let remainder = whole % 60
        if hours > 0 { return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时" }
        if minutes > 0 { return remainder > 0 ? "\(minutes) 分 \(remainder) 秒" : "\(minutes) 分钟" }
        return "\(remainder) 秒"
    }
}
