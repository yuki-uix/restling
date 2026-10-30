import AppKit
import SwiftUI
import PomodoroCore

@MainActor
private final class RestWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }
        else { super.keyDown(with: event) }
    }
}

private final class ClearRestHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

@MainActor
final class RestOverlayController {
    private let model: AppModel
    private var windows: [RestWindow] = []
    private var previousApplication: NSRunningApplication?
    var isVisible: Bool { !windows.isEmpty }
    var windowCount: Int { windows.count }

    init(model: AppModel) { self.model = model }

    func synchronize() {
        if model.showingRest && !isVisible { show() }
        else if !model.showingRest && isVisible { close() }
    }

    private func show(captureFocus: Bool = true) {
        if captureFocus { previousApplication = NSWorkspace.shared.frontmostApplication }
        let screens = NSScreen.screens
        let focusedScreen = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        for screen in screens {
            let window = RestWindow(contentRect: screen.frame, styleMask: [.borderless],
                                    backing: .buffered, defer: false, screen: screen)
            window.title = model.isPreview ? "Restling · 休息提醒预览" : "Restling · \(model.engine.phase.title)"
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isMovable = false
            window.hasShadow = false
            window.onEscape = { [weak model] in model?.dismissRest() }
            // Native behind-window material blurs the live desktop and windows.
            // It needs no screenshot capture or Screen Recording permission.
            let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            glass.material = .fullScreenUI
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.appearance = NSAppearance(named: .aqua)
            let content = ClearRestHostingView(rootView: RestView(model: model))
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.addSubview(content)
            window.contentView = glass
            window.setFrame(screen.frame, display: true)
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        if let index = screens.firstIndex(where: { $0 === focusedScreen }) {
            windows[index].makeKeyAndOrderFront(nil)
        } else { windows.first?.makeKeyAndOrderFront(nil) }
    }

    func close(restoreFocus: Bool = true) {
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        if restoreFocus, let app = previousApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier, !app.isTerminated {
            app.activate(options: [])
        }
        previousApplication = nil
    }

    func rebuildIfVisible() {
        guard isVisible else { return }
        let previous = previousApplication
        close(restoreFocus: false)
        previousApplication = previous
        show(captureFocus: false)
    }
}

private struct RestView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var forest: ForestStore
    @AppStorage("forestWeatherPreference.v1") private var weatherChoice = "automatic"

    init(model: AppModel) {
        self.model = model
        forest = model.forest
    }

    private let ink = Color(red: 0.16, green: 0.32, blue: 0.24)
    private var profile: PomodoroCore.ForestProfile { model.restForestProfile }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.94, green: 0.97, blue: 0.86).opacity(0.55),
                                        Color(red: 0.79, green: 0.87, blue: 0.75).opacity(0.36)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text(model.isPreview ? "休息森林 · 预览" : "\(profile.name) · 放松眼睛")
                            .font(.system(size: 13, weight: .medium, design: .rounded)).tracking(3)
                            .foregroundStyle(ink.opacity(0.65))
                        Text("抬头，看看远处")
                            .font(.system(size: min(34, geometry.size.height * 0.045), weight: .medium, design: .rounded))
                        Text("不用看着屏幕，森林会记住这次休息。")
                            .font(.system(size: 14)).foregroundStyle(ink.opacity(0.65))
                    }.padding(.top, max(28, geometry.size.height * 0.065))

                    ForestSceneView(profile: profile, resting: true,
                                    progress: model.isPreview ? 1 - model.restRemaining / 20 : model.progress,
                                    weather: ForestWeather(rawValue: weatherChoice))
                        .frame(maxWidth: 1500, maxHeight: .infinity)
                        .accessibilityLabel("\(profile.name)，已有 \(profile.trees.count) 棵成长树木")

                    VStack(spacing: 12) {
                        Text(clockText(model.restRemaining))
                            .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
                            .accessibilityLabel("休息剩余 \(clockText(model.restRemaining))")
                        Text(model.isPreview ? "这是预览，成长不会变化" : "休息结束后，自动回到原来的应用。")
                            .font(.system(size: 12)).foregroundStyle(ink.opacity(0.65))
                        if !model.isPreview {
                            HStack(spacing: 20) {
                                Button("3 分钟后休息") { model.snooze(minutes: 3) }
                                Button("5 分钟后休息") { model.snooze(minutes: 5) }
                            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(ink.opacity(0.65))
                        }
                        Button(model.isPreview ? "结束预览  esc" : "跳过本次休息  esc", action: model.dismissRest)
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
                            .padding(.vertical, 5).padding(.horizontal, 12)
                            .background(ink.opacity(0.055), in: Capsule())
                    }.padding(.bottom, max(25, geometry.size.height * 0.055))
                }
                .padding(.horizontal, 28)
                .foregroundStyle(ink)
            }
            .contextMenu {
                Text("剩余 \(clockText(model.restRemaining))")
                if !model.isPreview {
                    Button("3 分钟后休息") { model.snooze(minutes: 3) }
                    Button("5 分钟后休息") { model.snooze(minutes: 5) }
                }
                Button(model.isPreview ? "结束预览" : "跳过本次休息", action: model.dismissRest)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }
}
