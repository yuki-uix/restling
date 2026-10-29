import SwiftUI
import PomodoroCore

@MainActor
struct ForestOnboardingView: View {
    let settings: EyeRestSettings
    let onStart: () -> Void
    let onPreview: () -> Void
    let onLater: () -> Void
    @State private var page = 0
    @State private var emptyForest = ForestProfile(name: "你的休息森林")

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Restling · 休息森林", systemImage: "leaf").font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == page ? green : green.opacity(0.17))
                            .frame(width: index == page ? 24 : 7, height: 5)
                    }
                }.accessibilityLabel("第 \(page + 1) 步，共 3 步")
            }.foregroundStyle(green)

            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 27, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 13)).lineSpacing(5)
                    .foregroundStyle(ink.opacity(0.66)).fixedSize(horizontal: false, vertical: true)
            }.frame(height: 111, alignment: .topLeading)

            illustration.frame(height: 258)
                .background(green.opacity(0.025), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(green.opacity(0.10), lineWidth: 1))

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if page > 0 {
                    Button("上一步") { page -= 1 }.buttonStyle(.plain).foregroundStyle(green)
                }
                Button("稍后开始", action: onLater).buttonStyle(.plain)
                    .foregroundStyle(ink.opacity(0.55))
                Spacer()
                if page == 2 {
                    Button("先看看休息画面", action: onPreview).buttonStyle(.bordered)
                }
                Button(page < 2 ? "继续" : "开始第一个 \(settings.intervalMinutes) 分钟") {
                    if page < 2 { page += 1 } else { onStart() }
                }.buttonStyle(.borderedProminent).tint(green).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }.font(.system(size: 12))
            Text(page == 2 ? "预览不会增加成长。休息时无需操作，结束后自动返回。" : "森林会等你。现在，先照顾自己的眼睛。")
                .font(.system(size: 10)).foregroundStyle(ink.opacity(0.52))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(30).frame(width: 680, height: 606)
        .background(paper).foregroundStyle(ink)
        .preferredColorScheme(.light)
    }

    private var title: String {
        switch page {
        case 0: return "森林，从你第一次休息开始。"
        case 1: return "每用眼 \(settings.intervalMinutes) 分钟，\n留 \(settings.restSeconds) 秒给远处。"
        default: return "一次休息，一点生机。\n三次休息，一棵树。"
        }
    }

    private var subtitle: String {
        switch page {
        case 0: return "把目光还给远处，把休息留成森林。\n这里先留一小块空地，等第一抹绿慢慢出现。"
        case 1: return "到点时，森林会轻轻铺满屏幕，提醒你抬头看看远处。\n不用点击照料；休息结束，会自动回到原来的应用。"
        default: return "新芽长成树，林地也一点点扩展。\n跳过不会扣除进度，也不会让已经长成的树枯萎。"
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page {
        case 0:
            ForestSceneView(profile: emptyForest)
                .overlay(alignment: .bottom) {
                    Text("第一天 · 还没有树，也没有需要完成的任务")
                        .font(.system(size: 11)).foregroundStyle(ink.opacity(0.6)).padding(.bottom, 17)
                }
        case 1:
            VStack(spacing: 20) {
                HStack(spacing: 24) {
                    rhythmCard(value: settings.intervalMinutes, unit: "分钟用眼", symbol: "display")
                    Image(systemName: "arrow.right").foregroundStyle(green.opacity(0.5))
                    rhythmCard(value: settings.restSeconds, unit: "秒看向远处", symbol: "eye")
                }
                Text("自动提醒  →  放下操作、看向远处  →  自动返回")
                    .font(.system(size: 11)).foregroundStyle(ink.opacity(0.6))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { count in
                        VStack(spacing: 5) {
                            ForestSceneView(profile: demonstration(after: count))
                                .frame(height: 140)
                            Text("第 \(count) 次休息").font(.system(size: 11, weight: .medium))
                            Text(["新芽", "小树苗", "一棵树与更宽的土地"][count - 1])
                                .font(.system(size: 10)).foregroundStyle(ink.opacity(0.6))
                        }.frame(maxWidth: .infinity)
                    }
                }
                Text("成长示意").font(.system(size: 9)).foregroundStyle(ink.opacity(0.4))
            }.padding(12)
        }
    }

    private func rhythmCard(value: Int, unit: String, symbol: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(green)
            Text("\(value)").font(.system(size: 48, weight: .light, design: .rounded))
            Text(unit).font(.system(size: 12)).foregroundStyle(ink.opacity(0.65))
        }.frame(width: 176, height: 162)
            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }

    private func demonstration(after count: Int) -> ForestProfile {
        var profile = emptyForest
        for _ in 0..<count { profile.recordRest(id: UUID(), seconds: 20) }
        return profile
    }
}
