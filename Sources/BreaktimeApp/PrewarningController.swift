import AppKit
import SwiftUI

@MainActor
private final class PrewarningPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PrewarningHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A single invitation above the user's current workspace, without activating
/// Restling or taking keyboard focus from the foreground application.
@MainActor
final class PrewarningController {
    private let model: AppModel
    private let presentPanel: (NSPanel) -> Void
    private var panel: PrewarningPanel?

    var isVisible: Bool { panel != nil }
    var windowCount: Int { isVisible ? 1 : 0 }
    var panelForInspection: NSPanel? { panel }

    init(model: AppModel, presentPanel: ((NSPanel) -> Void)? = nil) {
        self.model = model
        // Tests construct and inspect the real native panel without ordering a
        // window onto the user's desktop. Production uses its normal presenter.
        self.presentPanel = presentPanel ?? { $0.orderFrontRegardless() }
    }

    func synchronize() {
        guard model.isPrewarningVisible else { close(); return }
        guard panel == nil else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }

        let size = NSSize(width: 360, height: 150)
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 20,
                           y: visible.maxY - size.height - 20,
                           width: size.width, height: size.height)
        let window = PrewarningPanel(contentRect: frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false, screen: screen)
        window.title = "Restling · 休息前提醒"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.contentView = PrewarningHostingView(rootView: PrewarningView(model: model))
        panel = window
        presentPanel(window)
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

@MainActor
private struct PrewarningView: View {
    @ObservedObject var model: AppModel
    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.46, green: 0.52, blue: 0.43)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(green)
                    .frame(width: 34, height: 34)
                    .background(green.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("快到休息时间了")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("还有 \(max(0, Int(ceil(model.engine.remaining)))) 秒，准备抬头看看远处。")
                        .font(.system(size: 11)).foregroundStyle(muted)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Button(action: model.dismissPrewarning) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(green.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭本次休息前提醒")
                .accessibilityIdentifier("prewarning.dismiss")
            }

            HStack(spacing: 7) {
                Button(action: model.nextPhase) {
                    Text("现在休息").font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(paper)
                        .background(green, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityIdentifier("prewarning.now")
                snoozeButton(minutes: 3)
                snoozeButton(minutes: 5)
            }.buttonStyle(.plain)

            HStack {
                Text("森林会等你，先把手边的事收个尾。")
                    .font(.system(size: 10)).foregroundStyle(muted)
                Spacer()
                Text(clockText(model.engine.remaining))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(width: 360, height: 150)
        .foregroundStyle(ink)
        .background(paper, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(green.opacity(0.12), lineWidth: 1))
        .preferredColorScheme(.light)
    }

    private func snoozeButton(minutes: Int) -> some View {
        Button { model.snooze(minutes: minutes) } label: {
            Text("\(minutes) 分钟后").font(.system(size: 12))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(green.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityIdentifier("prewarning.snooze\(minutes)")
    }
}
