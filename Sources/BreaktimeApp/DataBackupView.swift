import SwiftUI

/// A local data utility: importing is always reviewed before the controller
/// replaces the live archive. Timer and system login state are not imported.
@MainActor
struct DataBackupView: View {
    @ObservedObject private var controller: DataBackupController
    private let onClose: () -> Void

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let green = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let muted = Color(red: 0.42, green: 0.49, blue: 0.41)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)
    private let warning = Color(red: 0.57, green: 0.36, blue: 0.14)

    private var protectsUnreadableOriginal: Bool { controller.unreadableWarning != nil }

    init(controller: DataBackupController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    notices
                    if let review = controller.review {
                        restoreReview(review)
                    } else {
                        overview
                        backupActions
                        recoveryActions
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
            }

            Divider()
            footer
        }
        .frame(width: 680, height: 640)
        .background(paper)
        .foregroundStyle(ink)
        .tint(green)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(controller.review == nil ? "数据与备份" :
                        controller.review?.isRawOriginal == true ? "恢复原始存档" :
                        controller.review?.isUndo == true ? "恢复上次恢复前的数据" : "恢复备份")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(controller.review == nil
                     ? "给这台 Mac 上的森林留一份副本。"
                     : "先核对内容，再决定是否替换本机数据。")
                    .font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(green.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.isBusy)
            .accessibilityLabel("关闭数据与备份")
            .accessibilityIdentifier("data.backup.close")
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var notices: some View {
        if let error = controller.errorMessage {
            notice(error, symbol: "exclamationmark.circle", color: .red)
                .accessibilityIdentifier("data.backup.error")
        }
        if let message = controller.message {
            notice(message, symbol: "checkmark.circle", color: green)
                .accessibilityIdentifier("data.backup.message")
        }
        if let warningText = controller.unreadableWarning {
            notice(warningText, symbol: "exclamationmark.triangle", color: warning)
                .accessibilityIdentifier("data.backup.unreadableWarning")
        }
    }

    private var overview: some View {
        let summary = controller.currentSummary
        return VStack(alignment: .leading, spacing: 12) {
            Text(protectsUnreadableOriginal ? "当前临时森林（未计入原始存档）" : "全部本机数据")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 9) {
                countCard("森林档案", count: summary.profileCount, unit: "份")
                countCard("已长成树木", count: summary.treeCount, unit: "棵")
                countCard("累计完成休息", count: summary.completedRestCount, unit: "次")
                countCard("新增事件记录", count: summary.eventCount, unit: "条")
            }
            VStack(alignment: .leading, spacing: 5) {
                if protectsUnreadableOriginal {
                    Text("这些数字只来自临时森林，不代表原始存档的内容。可导出原始存档留存，或选择有效备份修复。")
                } else {
                    Text("详细记录始于 \(controller.recordingStartedAt.formatted(date: .numeric, time: .omitted))。")
                    Text("旧版累计进度会保留，不补写过去的逐次记录。记录代表计时结果，不验证是否望远。")
                }
            }
            .font(.system(size: 11)).foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("data.backup.overview")
    }

    private var backupActions: some View {
        card {
            Label(protectsUnreadableOriginal ? "保留或修复原始存档" : "备份全部森林", systemImage: "externaldrive")
                .font(.system(size: 13, weight: .semibold))
            Text(protectsUnreadableOriginal
                 ? "导出的是未能读取的原始文件，便于留存和排查。它不一定能直接恢复，原件保持不变。"
                 : "备份包含全部本机森林、树木、应用设置和休息事件。当前计时进度与 macOS 登录项不会随备份恢复。")
                .font(.system(size: 12)).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: controller.exportBackup) {
                    Label(protectsUnreadableOriginal ? "导出原始存档…" : "导出备份…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("data.backup.export")
                Button(action: controller.chooseBackup) {
                    Label("从备份恢复…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("data.backup.choose")
            }
            .font(.system(size: 12))
            .controlSize(.large)
            .disabled(controller.isBusy)
            Text(protectsUnreadableOriginal
                 ? "选择有效备份可以修复。恢复前会先另存原始数据，便于撤回。"
                 : "恢复前会先检查文件，并让你核对替换范围。")
                .font(.system(size: 11)).foregroundStyle(muted)
        }
    }

    @ViewBuilder
    private var recoveryActions: some View {
        if controller.recoveryAvailable {
            card {
                Label("已保留上次恢复前的数据", systemImage: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("每次恢复都会先保存当前数据，包括从安全副本恢复。你可以查看最近一次恢复前的内容，再决定是否恢复。")
                    .font(.system(size: 12)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("恢复上次恢复前的数据…", action: controller.prepareUndo)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("data.backup.undo")
                    Button("在 Finder 中显示安全副本", action: controller.revealRecoveryFile)
                        .buttonStyle(.link)
                        .accessibilityIdentifier("data.backup.revealRecovery")
                }
                .font(.system(size: 12))
                .disabled(controller.isBusy)
            }
        } else {
            Text(protectsUnreadableOriginal
                 ? "恢复有效备份前，会先保留当前原始数据；导出原始文件也可另行留存。"
                 : "恢复备份前，Restling 会先保存当前数据，便于撤回。")
                .font(.system(size: 11)).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restoreReview(_ review: BackupReview) -> some View {
        let current: BackupSummary? = protectsUnreadableOriginal ? nil : controller.currentSummary
        return VStack(alignment: .leading, spacing: 16) {
            card {
                Label(review.isUndo ? "上次恢复前的安全副本" : "选中的备份", systemImage: "doc")
                    .font(.system(size: 13, weight: .semibold))
                Text(review.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
                Text("备份时间：\(review.createdAt.formatted(date: .numeric, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }

            if review.isRawOriginal {
                card {
                    Label("不可读的原始存档", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("这份安全副本保留了无法解析的原始存档；档案、树木和事件数量暂时无法统计。")
                        .font(.system(size: 12)).foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("data.backup.rawOriginalReview")
            } else if let incoming = review.incoming {
                card {
                    HStack(spacing: 12) {
                        Text("替换范围").fontWeight(.semibold)
                        Spacer()
                        Text(protectsUnreadableOriginal ? "当前原始存档" : "当前本机")
                            .frame(width: 100, alignment: .trailing)
                        Text("备份内容").frame(width: 100, alignment: .trailing)
                    }
                    .font(.system(size: 11)).foregroundStyle(muted)
                    Divider()
                    comparisonRow("森林档案", current: current?.profileCount,
                                  incoming: incoming.profileCount, unit: "份")
                    comparisonRow("已长成树木", current: current?.treeCount,
                                  incoming: incoming.treeCount, unit: "棵")
                    comparisonRow("累计完成休息", current: current?.completedRestCount,
                                  incoming: incoming.completedRestCount, unit: "次")
                    comparisonRow("新增事件记录", current: current?.eventCount,
                                  incoming: incoming.eventCount, unit: "条")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(review.isRawOriginal ? "将回到此前不可读的状态" : "将替换全部本机数据",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text(review.isRawOriginal
                     ? "会恢复此前无法读取的原始存档和当时的应用设置。原件会保留，你仍可再次选择有效备份修复。此次操作也会先保存当前数据，形成新的安全副本。"
                     : review.isUndo
                     ? "会用上次恢复前的安全副本替换当前全部数据。上次恢复后新增的森林、设置更改和休息记录将被替换；你可以先返回并导出当前数据。此次操作也会先保留当前数据，形成新的安全副本。"
                     : "会用这份备份替换全部本机森林、应用设置和休息事件。恢复前会自动保存当前数据，之后可在此恢复上次恢复前的状态。")
                    .font(.system(size: 12))
                Text("恢复后提醒将保持暂停，从新的用眼间隔开始。macOS 登录项保持现有设置。")
                    .font(.system(size: 11))
            }
            .foregroundStyle(warning)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(warning.opacity(0.065), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityIdentifier("data.backup.replaceWarning")
        }
        .accessibilityIdentifier("data.backup.review")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if controller.isBusy {
                ProgressView().controlSize(.small)
                Text("正在处理本机数据…")
                    .font(.system(size: 11)).foregroundStyle(muted)
                    .accessibilityIdentifier("data.backup.busy")
            }
            Spacer()
            if let review = controller.review {
                Button("取消", action: controller.cancelReview)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("data.backup.cancelReview")
                Button(review.isRawOriginal ? "恢复原始存档" :
                        review.isUndo ? "恢复上次恢复前的数据" : "恢复备份", action: controller.confirmRestore)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("data.backup.confirm")
            } else {
                Button("完成", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("data.backup.done")
            }
        }
        .font(.system(size: 12))
        .disabled(controller.isBusy)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private func countCard(_ title: String, count: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 10)).foregroundStyle(muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(count)").font(.system(size: 22, weight: .medium, design: .rounded))
                Text(unit).font(.system(size: 10)).foregroundStyle(muted)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(green.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(count) \(unit)")
    }

    private func comparisonRow(_ title: String, current: Int?, incoming: Int, unit: String) -> some View {
        let currentText = current.map { "\($0) \(unit)" } ?? "未能读取"
        return HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text(currentText).frame(width: 100, alignment: .trailing)
            Text("\(incoming) \(unit)").frame(width: 100, alignment: .trailing)
                .fontWeight(.medium)
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，当前本机 \(currentText)，备份内容 \(incoming) \(unit)")
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(green.opacity(0.10), lineWidth: 1))
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }

    private func close() {
        guard !controller.isBusy else { return }
        if controller.review != nil { controller.cancelReview() }
        onClose()
    }
}
