import AppKit
import SwiftUI
import PomodoroCore

private let forestInk = Color(red: 0.16, green: 0.28, blue: 0.23)
private let forestAccent = Color(red: 0.23, green: 0.43, blue: 0.31)
private let forestMuted = Color(red: 0.46, green: 0.52, blue: 0.43)
private let forestPaper = Color(red: 0.97, green: 0.96, blue: 0.91)

private enum ForestMainSheet: Identifiable, Equatable {
    case settings, dataBackup, ecology, createProfile, renameProfile, onboarding
    case catalogue(ForestSpecies)
    var id: String {
        switch self {
        case .settings: return "settings"
        case .dataBackup: return "dataBackup"
        case .ecology: return "ecology"
        case .createProfile: return "createProfile"
        case .renameProfile: return "renameProfile"
        case .onboarding: return "onboarding"
        case .catalogue(let species): return "catalogue.\(species.rawValue)"
        }
    }
}

@MainActor
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var forest: ForestStore
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var loginItem: LoginItemController
    private let backupController: DataBackupController
    private let onShowUpdates: () -> Void
    @State private var sheet: ForestMainSheet?
    @State private var profileName = ""
    @State private var selectedGroveIndex: Int?
    @AppStorage("forestWeatherPreference.v1") private var weatherChoice = "automatic"
    @AppStorage("restForestOnboarding.v1") private var hasSeenOnboarding = false
    private let onboardingEnabled: Bool

    init(model: AppModel, updater: UpdateChecker, loginItem: LoginItemController,
         backupController: DataBackupController, onShowUpdates: @escaping () -> Void,
         onboardingEnabled: Bool = true) {
        self.model = model
        _forest = ObservedObject(wrappedValue: model.forest)
        self.updater = updater
        self.loginItem = loginItem
        self.backupController = backupController
        _weatherChoice = AppStorage(wrappedValue: "automatic", "forestWeatherPreference.v1", store: model.preferenceDefaults)
        _hasSeenOnboarding = AppStorage(wrappedValue: false, "restForestOnboarding.v1", store: model.preferenceDefaults)
        self.onShowUpdates = onShowUpdates
        self.onboardingEnabled = onboardingEnabled
    }

    private var profile: ForestProfile { forest.current }
    private var entireForest: ForestLandscape { ForestLandscape(profile: profile) }
    private var displayedGrove: Int { min(entireForest.currentGroveIndex, max(0, selectedGroveIndex ?? entireForest.currentGroveIndex)) }
    private var landscape: ForestLandscape { ForestLandscape(completedRests: entireForest.rests(inGrove: displayedGrove)) }
    private var ecology: ForestEcology { ForestEcology(profile: profile) }
    private var discoveryReward: ForestStore.RestReward? {
        guard let reward = forest.latestRestReward, reward.profileID == profile.id,
              ForestEcology.milestone(at: reward.completedRests) != nil ||
              reward.completedRests == ForestSpecies.birch.unlockAfter else { return nil }
        return reward
    }
    private var quickSpecies: [ForestSpecies] {
        var result = Array(ForestSpecies.allCases.prefix(3))
        if !result.contains(profile.selectedSpecies) { result[2] = profile.selectedSpecies }
        return result
    }
    private var forestStatusText: String {
        if profile.completedRests == 0 { return "这里还没有树。第一抹绿，会在你休息之后出现。" }
        if displayedGrove < entireForest.currentGroveIndex {
            let landmarks = ecology.milestones(inGrove: displayedGrove).map(\.title).joined(separator: "、")
            return landmarks.isEmpty ? landscape.stageTitle : landscape.stageTitle + " · " + landmarks
        }
        return profile.completedRests < 24 ? landscape.stageTitle + " · " + landscape.nextMilestoneText : ecology.nextMilestoneText
    }
    private var growthTitle: String {
        switch profile.growthStage {
        case 1: return profile.completedRests == 1 ? "第一抹绿，刚刚发芽" : "下一棵树，刚刚发芽"
        case 2: return "小树苗，快要长成了"
        default: return profile.completedRests == 0 ? "第一抹绿，从一次休息开始" : "下一次休息，再添一点生机"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 18) {
                forestCard
                timerCard.frame(width: 254)
            }.frame(height: 360)
            HStack(alignment: .top, spacing: 18) {
                growthCard
                speciesCard
            }.frame(height: 188)
            footer
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(width: 900, height: 740, alignment: .topLeading)
        .background(forestPaper)
        .foregroundStyle(forestInk)
        .tint(forestAccent)
        .preferredColorScheme(.light)
        .sheet(item: $sheet) { currentSheet in
            switch currentSheet {
            case .settings: settingsSheet
            case .dataBackup: DataBackupView(controller: backupController, onClose: { sheet = nil })
            case .ecology:
                ForestEcologyView(forest: forest, onViewGrove: { index in
                    selectedGroveIndex = index
                    sheet = nil
                }, onClose: { sheet = nil })
            case .createProfile, .renameProfile: profileSheet(currentSheet)
            case .catalogue(let species):
                ForestCatalogueView(forest: forest, initiallySelected: species,
                                    onClose: { sheet = nil })
            case .onboarding:
                ForestOnboardingView(settings: model.eyeRestSettings,
                    onStart: {
                        hasSeenOnboarding = true
                        sheet = nil
                        if !model.engine.isRunning { model.toggleRunning() }
                    }, onPreview: {
                        hasSeenOnboarding = true
                        sheet = nil
                        DispatchQueue.main.async { model.preview() }
                    }, onLater: {
                        hasSeenOnboarding = true
                        sheet = nil
                    })
            }
        }
        .onAppear {
            if onboardingEnabled && !hasSeenOnboarding { sheet = .onboarding }
        }
        .onChange(of: profile.id) { _ in selectedGroveIndex = nil }
        .onChange(of: profile.completedRests) { _ in selectedGroveIndex = nil }
        .onReceive(NotificationCenter.default.publisher(for: .init("Restling.showReminderSettings"))) { _ in
            sheet = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("Restling.showDataBackup"))) { _ in
            sheet = .dataBackup
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("Restling.showForestEcology"))) { _ in
            sheet = .ecology
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Restling").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("把目光还给远处，把休息留成森林。")
                    .font(.system(size: 12)).foregroundStyle(forestMuted)
            }
            Spacer()
            Menu {
                Section("切换本机档案") {
                    ForEach(forest.profiles) { item in
                        Button {
                            forest.selectProfile(item.id)
                        } label: {
                            if item.id == forest.activeProfileID {
                                Label(item.name, systemImage: "checkmark")
                            } else { Text(item.name) }
                        }
                    }
                }
                Divider()
                Button("新建森林档案") {
                    profileName = ""
                    sheet = .createProfile
                }
                Button("给森林改名") {
                    profileName = profile.name
                    sheet = .renameProfile
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle")
                    Text(profile.name).lineLimit(1)
                }.font(.system(size: 12, weight: .medium))
            }.menuStyle(.borderlessButton).fixedSize().frame(maxWidth: 185)
            Button(action: onShowUpdates) {
                Label(updater.shouldShowBanner ? "有新版本" : "检查更新",
                      systemImage: updater.shouldShowBanner ? "arrow.down.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 11, weight: updater.shouldShowBanner ? .semibold : .regular))
                    .foregroundStyle(forestAccent)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(forestAccent.opacity(updater.shouldShowBanner ? 0.13 : 0.045), in: Capsule())
            }.buttonStyle(.plain)
                .accessibilityLabel(updater.shouldShowBanner ? "发现新版本，查看更新说明" : "检查更新与版本信息")
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 16))
                    .frame(width: 30, height: 30)
            }.buttonStyle(.plain).help("提醒与节奏设置").accessibilityLabel("提醒与节奏设置")
        }.frame(height: 52)
    }

    private var forestCard: some View {
        ZStack(alignment: .topLeading) {
            ForestSceneView(profile: profile, groveIndex: displayedGrove,
                            weather: ForestWeather(rawValue: weatherChoice))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(profile.name).lineLimit(1)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Spacer(minLength: 6)
                    ForestWeatherPicker(seed: profile.seed, choice: $weatherChoice)
                    if entireForest.groveCount > 1 {
                        groveNavigation
                    }
                }
                Text(forestStatusText)
                    .font(.system(size: 11)).foregroundStyle(forestMuted).lineLimit(2)
                Button { sheet = .ecology } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "map")
                        Text("林地手记 · \(ecology.unlockedMilestones.count) / \(ForestEcologyMilestone.allCases.count)")
                        Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold))
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(forestAccent)
                }.buttonStyle(.plain).padding(.top, 2)
                    .accessibilityLabel("查看林地手记与生态里程碑")
                    .accessibilityIdentifier("main.ecology")
                Spacer()
                Group {
                    if let reward = forest.latestRestReward, reward.profileID == profile.id,
                       displayedGrove == entireForest.currentGroveIndex {
                        Text(reward.title).fontWeight(.semibold)
                    } else {
                        Text(displayedGrove < entireForest.currentGroveIndex ? "这片森林，留住了你曾经的休息。" : "森林会等你。现在，先照顾自己的眼睛。")
                    }
                }.font(.system(size: 10)).foregroundStyle(forestInk.opacity(0.76)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(forestPaper.opacity(0.88), in: Capsule())
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 6)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(forestAccent.opacity(0.10), lineWidth: 1))
    }

    private var groveNavigation: some View {
        HStack(spacing: 7) {
            Button { selectedGroveIndex = displayedGrove - 1 } label: {
                Image(systemName: "chevron.left").frame(width: 17, height: 20)
            }.disabled(displayedGrove == 0).accessibilityLabel("查看上一片林地")
            Text("第 \(displayedGrove + 1) 片 / 共 \(entireForest.groveCount) 片")
                .font(.system(size: 10)).monospacedDigit()
            Button { selectedGroveIndex = displayedGrove + 1 } label: {
                Image(systemName: "chevron.right").frame(width: 17, height: 20)
            }.disabled(displayedGrove == entireForest.currentGroveIndex).accessibilityLabel("查看下一片林地")
        }.buttonStyle(.plain).foregroundStyle(forestMuted)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(forestPaper.opacity(0.9), in: Capsule())
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(model.engine.phase == .focus ? "距下次休息" : "休息中", systemImage: model.engine.phase.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle().fill(model.engine.isRunning ? forestAccent : forestMuted.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(model.isSnoozing ? "已推迟" : model.pauseReason != nil ? "暂缓中" :
                    model.engine.isRunning ? (model.engine.phase == .focus ? "用眼中" : "休息中") : model.hasStarted ? "已暂停" : "尚未开始")
                    .font(.system(size: 10)).foregroundStyle(forestMuted)
            }
            Spacer(minLength: 0)
            Text(clockText(model.displayedRemaining))
                .font(.system(size: 54, weight: .light, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6).lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("剩余 \(clockText(model.displayedRemaining))")
            Text("每 \(model.eyeRestSettings.intervalMinutes) 分钟 · 放松 \(model.eyeRestSettings.restSeconds) 秒")
                .font(.system(size: 11)).foregroundStyle(forestMuted)
                .frame(maxWidth: .infinity)
            ProgressView(value: model.progress).tint(forestAccent)
            Spacer(minLength: 0)
            Button {
                if model.doNotDisturbUntil != nil { model.endDoNotDisturb() }
                else { model.toggleRunning() }
            } label: {
                Label(model.doNotDisturbUntil != nil ? "结束临时勿扰" : model.toggleTitle,
                      systemImage: model.doNotDisturbUntil == nil && model.wantsRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            HStack {
                Button(model.phaseActionTitle, action: model.nextPhase)
                    .disabled(!model.canRestNow)
                Spacer()
                Button("重置", action: model.reset)
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(forestMuted)
            Divider().overlay(forestAccent.opacity(0.05))
            Text(model.statusDescription)
                .font(.system(size: 11)).foregroundStyle(forestMuted).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 25)
            HStack {
                Button(action: model.preview) {
                    Label("预览休息", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                }.disabled(!model.canPreview)
                Menu {
                    Button("勿扰 30 分钟") { model.pauseFor(minutes: 30) }
                    Button("勿扰 1 小时") { model.pauseFor(minutes: 60) }
                    if model.doNotDisturbUntil != nil {
                        Divider()
                        Button("结束临时勿扰", action: model.endDoNotDisturb)
                    }
                } label: { Label("勿扰", systemImage: "moon") }
            }.buttonStyle(.bordered).controlSize(.small)
        }.padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(forestAccent.opacity(0.10), lineWidth: 1))
    }

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(discoveryReward?.title ?? growthTitle).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(profile.growthStage) / 3")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(forestMuted)
            }
            ProgressView(value: profile.growthProgress).tint(forestAccent)
            Text(discoveryReward?.detail ?? "再完成 \(profile.restsUntilTree) 次休息，种下这棵\(profile.selectedSpecies.title)。")
                .font(.system(size: 11)).foregroundStyle(forestMuted).lineLimit(2)
            HStack(spacing: 0) {
                statistic("累计种下", value: "\(profile.trees.count)", unit: "棵树")
                Spacer(minLength: 6)
                statistic("完成休息", value: "\(profile.completedRests)", unit: "次")
                Spacer(minLength: 6)
                statistic("放松时光", value: "\(Int(profile.totalRestSeconds < 60 ? profile.totalRestSeconds : profile.totalRestSeconds / 60))", unit: profile.totalRestSeconds < 60 ? "秒" : "分钟")
            }.padding(.top, 1)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(forestAccent.opacity(0.10), lineWidth: 1))
    }

    private func statistic(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(forestMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .medium, design: .rounded))
                Text(unit).font(.system(size: 10)).foregroundStyle(forestMuted)
            }
        }
    }

    private var speciesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择培育树种").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    sheet = .catalogue(profile.selectedSpecies)
                } label: {
                    HStack(spacing: 3) {
                        Text("查看树种图鉴")
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    }.font(.system(size: 10)).foregroundStyle(forestAccent)
                }.buttonStyle(.plain).accessibilityLabel("查看树种图鉴")
            }
            HStack(spacing: 9) {
                ForEach(quickSpecies) { species in
                    speciesButton(species)
                }
            }
            Text("共 \(ForestSpecies.allCases.count) 种树 · 图鉴可预览每个成长阶段")
                .font(.system(size: 10)).foregroundStyle(forestMuted)
        }.padding(18).frame(width: 350, height: 188, alignment: .topLeading)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(forestAccent.opacity(0.10), lineWidth: 1))
    }

    private func speciesButton(_ species: ForestSpecies) -> some View {
        let unlocked = profile.completedRests >= species.unlockAfter
        let selected = profile.selectedSpecies == species
        return Button {
            sheet = .catalogue(species)
        } label: {
            VStack(spacing: 5) {
                MiniForestTree(species: species).frame(width: 34, height: 38)
                HStack(spacing: 3) {
                    if !unlocked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    Text(species.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                }
                Text(unlocked ? (selected ? "已选 · 查看" : "查看与选择") : "\(species.unlockAfter) 次解锁 · 预览")
                    .font(.system(size: 8)).foregroundStyle(forestMuted)
            }.frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(selected ? forestAccent.opacity(0.10) : Color.white.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? forestAccent.opacity(0.5) : forestAccent.opacity(0.09), lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(species.title)，\(unlocked ? (selected ? "已选，可查看详情" : "可查看与选择") : "休息 \(species.unlockAfter) 次解锁，可预览")")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("本机档案 · 云同步未连接", systemImage: "externaldrive")
                Button("数据与备份") { sheet = .dataBackup }.buttonStyle(.link)
                    .accessibilityIdentifier("main.dataBackup")
                Button("新手指引") { sheet = .onboarding }.buttonStyle(.link)
                Spacer()
                Text("预览和跳过不计成长 · 暂停不会让树枯萎")
            }.font(.system(size: 10)).foregroundStyle(forestMuted)
            if let error = forest.errorMessage {
                Text(error).font(.system(size: 10)).foregroundStyle(.red)
            }
        }
    }

    private var settingsSheet: some View {
        ReminderSettingsView(model: model, loginItem: loginItem, onClose: { sheet = nil })
    }

    private func profileSheet(_ kind: ForestMainSheet) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(kind == .createProfile ? "种下另一片森林" : "给森林起个名字")
                .font(.system(size: 21, weight: .semibold))
            Text("每份本机档案都有独立的树木和休息进度。")
                .font(.system(size: 12)).foregroundStyle(forestMuted)
            TextField("森林名字", text: $profileName).textFieldStyle(.roundedBorder)
                .accessibilityLabel("森林名字")
            HStack {
                Spacer()
                Button("取消") { sheet = nil }.keyboardShortcut(.cancelAction)
                Button(kind == .createProfile ? "开始种植" : "保存名字") {
                    if kind == .createProfile { forest.createProfile(name: profileName) }
                    else { forest.renameCurrent(profileName) }
                    sheet = nil
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 410).background(forestPaper).tint(forestAccent)
    }


}

/// Small, original block sprites keep the tree picker consistent with the pixel scene.
private struct MiniForestTree: View {
    let species: ForestSpecies
    @ViewBuilder
    var body: some View {
        if [.birch, .willow, .ginkgo].contains(species) {
            ForestTreeIllustration(species: species, stage: 3)
                .accessibilityHidden(true)
        } else {
          Canvas { context, size in
            let scale = min(size.width / 16, size.height / 18)
            let origin = CGPoint(x: (size.width - 16 * scale) / 2, y: (size.height - 18 * scale) / 2)
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: origin.x + x * scale, y: origin.y + y * scale,
                                         width: w * scale, height: h * scale)), with: .color(color))
            }
            block(7, 11, 2, 6, Color(red: 0.48, green: 0.34, blue: 0.23))
            switch species {
            case .oak:
                block(3, 3, 10, 9, Color(red: 0.32, green: 0.53, blue: 0.32))
                block(1, 6, 14, 6, Color(red: 0.32, green: 0.53, blue: 0.32))
                block(5, 1, 6, 12, Color(red: 0.32, green: 0.53, blue: 0.32))
                block(4, 4, 4, 3, Color(red: 0.55, green: 0.68, blue: 0.38))
                block(2, 8, 4, 2, Color(red: 0.43, green: 0.61, blue: 0.35))
            case .pine:
                block(7, 0, 2, 3, Color(red: 0.21, green: 0.43, blue: 0.36))
                block(5, 3, 6, 3, Color(red: 0.23, green: 0.48, blue: 0.37))
                block(3, 6, 10, 4, Color(red: 0.25, green: 0.50, blue: 0.38))
                block(1, 10, 14, 4, Color(red: 0.21, green: 0.43, blue: 0.36))
                block(4, 7, 3, 2, Color(red: 0.42, green: 0.61, blue: 0.44))
            case .blossom:
                block(4, 2, 8, 11, Color(red: 0.85, green: 0.56, blue: 0.61))
                block(1, 5, 14, 6, Color(red: 0.85, green: 0.56, blue: 0.61))
                block(3, 4, 10, 5, Color(red: 0.95, green: 0.72, blue: 0.72))
                block(5, 2, 5, 2, Color(red: 0.99, green: 0.83, blue: 0.77))
                block(2, 7, 3, 2, Color(red: 0.99, green: 0.83, blue: 0.77))
            case .birch, .willow, .ginkgo: break
            }
            block(5, 17, 6, 1, forestAccent.opacity(0.18))
          }.accessibilityHidden(true)
        }
    }
}

private struct ForestWeatherPicker: View {
    let seed: UInt64
    @Binding var choice: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quietDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 2, paused: reduceMotion)) { timeline in
            let timestamp = (reduceMotion ? quietDate : timeline.date).timeIntervalSinceReferenceDate
            let weather = ForestWeather(rawValue: choice) ?? ForestAtmosphere.sample(at: timestamp, seed: seed).weather
            Menu {
                Section("林间天气") {
                    Button { choice = "automatic" } label: {
                        if choice == "automatic" { Label("自动变换", systemImage: "checkmark") }
                        else { Text("自动变换") }
                    }
                    Divider()
                    ForEach(ForestWeather.allCases) { item in
                        Button { choice = item.rawValue } label: {
                            if choice == item.rawValue { Label(item.title, systemImage: "checkmark") }
                            else { Label(item.title, systemImage: item.symbol) }
                        }
                    }
                    Divider()
                    Text("场景氛围，随时间缓慢变化")
                }
            } label: {
                Label(choice == "automatic" ? "自动 · \(weather.title)" : weather.title,
                      systemImage: weather.symbol)
                    .font(.system(size: 10)).foregroundStyle(forestAccent)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(forestPaper.opacity(0.9), in: Capsule())
            .help("林间天气是森林里的氛围，可自动变换或手动选择。")
            .accessibilityLabel("林间天气，\(choice == "automatic" ? "自动变换，" : "")\(weather.title)")
        }
    }
}
