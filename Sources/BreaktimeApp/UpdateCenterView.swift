import AppKit
import SwiftUI
import PomodoroCore

@MainActor
struct UpdateCenterView: View {
    @ObservedObject var checker: UpdateChecker
    let onClose: () -> Void
    @State private var copied = false

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.46, green: 0.52, blue: 0.43)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)

    private var checking: Bool {
        if case .checking = checker.state { return true }
        return false
    }

    private var unsupported: Bool {
        guard let minimum = checker.availableRelease?.minimumMacOSVersion else { return false }
        return minimum > checker.currentMacOSVersion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard
            if let release = checker.availableRelease {
                releaseDetails(release)
            } else {
                emptyDetails
            }
            automaticChecks
            footer
        }
        .padding(28)
        .frame(width: 680, height: 620)
        .background(paper).foregroundStyle(ink).tint(green)
        .preferredColorScheme(.light)
        .onChange(of: checker.availableRelease?.version.description) { _ in copied = false }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("应用更新").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("Restling · 当前版本 \(checker.currentVersion.description)")
                    .font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(green.opacity(0.07), in: Circle())
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭应用更新")
        }.frame(height: 51)
    }

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 13) {
            Group {
                if checking { ProgressView().controlSize(.small) }
                else { Image(systemName: statusSymbol).font(.system(size: 21, weight: .regular)) }
            }.foregroundStyle(green).frame(width: 29)
            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle).font(.system(size: 14, weight: .semibold))
                Text(statusDescription).font(.system(size: 11)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(green.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }

    private func releaseDetails(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("版本 \(release.version.description) 的新内容")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Link(destination: release.releaseURL) {
                    Label("查看发布页", systemImage: "arrow.up.right")
                        .font(.system(size: 11))
                }
            }
            ScrollView {
                Text(release.releaseNotes.isEmpty ? "这个版本暂未附更新说明，可前往发布页了解详情。" : release.releaseNotes)
                    .font(.system(size: 12)).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(green.opacity(0.08), lineWidth: 1))

            if unsupported {
                Label("需要 macOS \(release.minimumMacOSVersion?.description ?? "更新版本") 或更新版本。", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(muted)
            } else if let command = checker.configuration?.homebrewCask?.upgradeCommand {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(command).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                    }
                    Button(copied ? "已复制" : "复制升级命令") {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(command, forType: .string)
                    }.controlSize(.small).accessibilityLabel(copied ? "升级命令已复制" : "复制 Homebrew 升级命令")
                }.padding(11).frame(height: 43)
                    .background(green.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                Text("在终端运行以上命令完成升级。")
                    .font(.system(size: 10)).foregroundStyle(muted)
            } else {
                Text("此版本尚未连接 Homebrew 发行渠道，可先查看发布页了解升级方式。")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyDetails: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 33, weight: .light)).foregroundStyle(green.opacity(0.55))
            Text(checker.configuration == nil ? "公开更新源接通后，新版本会出现在这里。" : "发现新版本后，这里会显示新功能和升级方式。")
                .font(.system(size: 12)).foregroundStyle(muted)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var automaticChecks: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("启动后自动检查更新").font(.system(size: 12, weight: .medium))
                Text(checker.configuration == nil ? "连接发布源后生效，每天最多检查一次。" : "每天最多检查一次，有新版时在应用内轻声提示。")
                    .font(.system(size: 10)).foregroundStyle(muted)
            }
            Spacer()
            Toggle("启动后自动检查更新", isOn: $checker.automaticChecksEnabled)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(.vertical, 11)
            .overlay(alignment: .top) { Divider().overlay(green.opacity(0.05)) }
    }

    private var footer: some View {
        HStack {
            Text(lastCheckedText).font(.system(size: 10)).foregroundStyle(muted)
            Spacer()
            if checker.shouldShowBanner {
                Button("忽略此版本") {
                    checker.dismissAvailableVersion()
                    onClose()
                }.controlSize(.large)
            }
            Button("完成", action: onClose).controlSize(.large)
            Button {
                copied = false
                Task { await checker.checkForUpdates(manually: true) }
            } label: {
                Text(checking ? "正在检查…" : "检查更新").frame(minWidth: 73)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(checking || checker.configuration == nil)
                .accessibilityLabel(checking ? "正在检查更新" : "立即检查更新")
        }.frame(height: 34)
    }

    private var lastCheckedText: String {
        guard let date = checker.lastCheckedAt else { return "尚未检查更新" }
        return "上次检查：\(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var statusTitle: String {
        if !checking, checker.lastError != nil {
            return checker.availableRelease == nil ? "暂时无法检查更新" : "已找到新版本，暂时无法刷新"
        }
        switch checker.state {
        case .notConfigured: return "尚未连接更新源"
        case .idle: return "可以检查新版本"
        case .checking: return "正在检查更新"
        case .upToDate: return "当前已是最新版本"
        case .available: return "发现新版本"
        case .failed: return "暂时无法检查更新"
        case .unsupported: return "新版需要更新的 macOS"
        }
    }

    private var statusDescription: String {
        if !checking, let error = checker.lastError { return error }
        switch checker.state {
        case .notConfigured:
            return "此本机版尚未连接公开更新源；发布地址配置后即可检查。"
        case .idle:
            return "点击“检查更新”，了解是否有新的功能。"
        case .checking:
            return "正在获取发布信息，休息提醒会继续运行。"
        case .upToDate:
            return "目前没有检测到比 \(checker.currentVersion.description) 更新的版本。"
        case .available:
            return checker.lastError ?? "可以先阅读更新说明，再通过 Homebrew 升级。"
        case .failed(let message):
            return message
        case .unsupported:
            return "你可以查看新版内容，升级应用前需要先满足系统版本要求。"
        }
    }

    private var statusSymbol: String {
        if !checking, checker.lastError != nil { return "wifi.exclamationmark" }
        switch checker.state {
        case .notConfigured: return "link.badge.plus"
        case .idle, .checking: return "arrow.clockwise"
        case .upToDate: return "checkmark.circle"
        case .available: return "sparkles"
        case .failed: return "wifi.exclamationmark"
        case .unsupported: return "exclamationmark.circle"
        }
    }
}

@MainActor
struct UpdateAvailableBanner: View {
    @ObservedObject var checker: UpdateChecker
    let onOpen: () -> Void

    var body: some View {
        if checker.shouldShowBanner, let release = checker.availableRelease {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text("Restling \(release.version.description) 有新内容了。")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button("查看更新", action: onOpen).buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                Button("稍后") { checker.dismissAvailableVersion() }.buttonStyle(.plain)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13).frame(height: 46)
            .foregroundStyle(Color(red: 0.23, green: 0.43, blue: 0.31))
            .background(Color(red: 0.23, green: 0.43, blue: 0.31).opacity(0.065),
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
