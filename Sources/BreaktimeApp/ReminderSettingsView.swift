import AppKit
import SwiftUI
import PomodoroCore

/// Reminder edits remain a draft until Save. The login-item control is a
/// separate system preference and deliberately applies immediately.
@MainActor
struct ReminderSettingsView: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var loginItem: LoginItemController
    private let onClose: () -> Void
    @State private var draft: ReminderPreferences
    @State private var intervalMinutes: Int
    @State private var restSeconds: Int

    private let ink = Color(red: 0.16, green: 0.28, blue: 0.23)
    private let muted = Color(red: 0.42, green: 0.49, blue: 0.41)
    private let accent = Color(red: 0.23, green: 0.43, blue: 0.31)
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.91)
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
    private let weekdayTitles = [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"]

    init(model: AppModel, loginItem: LoginItemController, onClose: @escaping () -> Void) {
        self.model = model
        self.loginItem = loginItem
        self.onClose = onClose
        _draft = State(initialValue: model.reminderPreferences)
        _intervalMinutes = State(initialValue: model.eyeRestSettings.intervalMinutes)
        _restSeconds = State(initialValue: model.eyeRestSettings.restSeconds)
    }

    private var hasEmptySchedule: Bool { draft.scheduleEnabled && draft.weekdays.isEmpty }
    private var pendingEyeRest: EyeRestSettings {
        EyeRestSettings(intervalMinutes: intervalMinutes, restSeconds: restSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("提醒与休息设置")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("节奏与提醒偏好会在保存后生效。")
                    .font(.system(size: 13)).foregroundStyle(muted)
            }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rhythmGroup
                    scheduleGroup
                    prewarningGroup
                    absenceGroup
                    soundGroup
                    loginGroup
                }.padding(.horizontal, 26).padding(.bottom, 18)
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if hasEmptySchedule {
                    Text("请至少选择一个提醒日，或关闭工作时段限制。")
                        .font(.system(size: 12)).foregroundStyle(Color.red)
                        .accessibilityIdentifier("reminder.settings.emptyWeekdays")
                }
                HStack(spacing: 12) {
                    Text("森林进度会保留。")
                        .font(.system(size: 12)).foregroundStyle(muted)
                    Spacer()
                    Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                    Button("保存设置", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(hasEmptySchedule)
                        .accessibilityIdentifier("reminder.settings.save")
                }
            }.padding(.horizontal, 26).padding(.vertical, 16)
        }
        .frame(width: 650, height: 690)
        .background(paper)
        .foregroundStyle(ink)
        .tint(accent)
        .preferredColorScheme(.light)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var rhythmGroup: some View {
        group("休息节奏") {
            HStack(spacing: 24) {
                numberSetting("用眼间隔", value: $intervalMinutes, range: 1...120, unit: "分钟")
                numberSetting("放松时长", value: $restSeconds, range: 5...180, unit: "秒")
            }
            note("更改节奏会重新开始本次计时。每次休息使用相同的时长。")
            Button("恢复 20 分钟／20 秒") { intervalMinutes = 20; restSeconds = 20 }
                .buttonStyle(.link).font(.system(size: 12))
        }
    }

    private var scheduleGroup: some View {
        group("工作日与提醒时段") {
            Toggle("仅在选定时段提醒", isOn: $draft.scheduleEnabled)
                .accessibilityIdentifier("reminder.settings.scheduleEnabled")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        Toggle(weekdayTitles[day]!, isOn: weekdayBinding(day))
                            .toggleStyle(.button)
                            .font(.system(size: 12))
                            .accessibilityLabel("\(weekdayTitles[day]!)提醒")
                    }
                }
                HStack(spacing: 30) {
                    DatePicker("开始", selection: clockBinding(\.startMinute), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .accessibilityLabel("提醒时段开始时间")
                    DatePicker("结束", selection: clockBinding(\.endMinute), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .accessibilityLabel("提醒时段结束时间")
                }
                if draft.scheduleEnabled && draft.weekdays.isEmpty {
                    Text("尚未选择提醒日。")
                        .font(.system(size: 12)).foregroundStyle(Color.red)
                }
            }.disabled(!draft.scheduleEnabled)
            note(scheduleExplanation)
        }
    }

    private var prewarningGroup: some View {
        group("提前预告") {
            choiceRow("休息前轻预告") {
                Picker("休息前轻预告", selection: $draft.prewarningSeconds) {
                    Text("关闭").tag(0)
                    ForEach([10, 20, 30], id: \.self) { Text("提前 \($0) 秒").tag($0) }
                    if ![0, 10, 20, 30].contains(draft.prewarningSeconds) {
                        Text("提前 \(draft.prewarningSeconds) 秒").tag(draft.prewarningSeconds)
                    }
                }.pickerStyle(.menu)
            }
            note("预告不会进入全屏，可以选择稍后 3 分钟或 5 分钟休息。")
        }
    }

    private var absenceGroup: some View {
        group("离席与返回") {
            Toggle("无键鼠操作时自动暂停", isOn: $draft.idlePauseEnabled)
                .accessibilityIdentifier("reminder.settings.idlePauseEnabled")
            choiceRow("离席判定时间") {
                Picker("离席判定时间", selection: $draft.idleThresholdSeconds) {
                    ForEach([120, 300, 600, 900], id: \.self) { Text("\($0 / 60) 分钟").tag($0) }
                    if ![120, 300, 600, 900].contains(draft.idleThresholdSeconds) {
                        Text("\(draft.idleThresholdSeconds) 秒").tag(draft.idleThresholdSeconds)
                    }
                }.pickerStyle(.menu)
            }.disabled(!draft.idlePauseEnabled)
            choiceRow("返回后的缓冲") {
                Picker("返回后的缓冲", selection: $draft.returnGraceSeconds) {
                    Text("不额外缓冲").tag(0)
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) 秒").tag($0) }
                    if ![0, 15, 30, 60].contains(draft.returnGraceSeconds) {
                        Text("\(draft.returnGraceSeconds) 秒").tag(draft.returnGraceSeconds)
                    }
                }.pickerStyle(.menu)
            }
            note("锁屏、系统睡眠和离席期间不发出提醒，也不会自动增加森林成长。")
        }
    }

    private var soundGroup: some View {
        group("声音") {
            Toggle("休息开始时播放提示音", isOn: $draft.startSoundEnabled)
            Toggle("休息结束时播放提示音", isOn: $draft.endSoundEnabled)
            note("预览保持静音；勿扰或提醒时段外不会播放提示音。")
        }
    }

    private var loginGroup: some View {
        group("开机启动") {
            Toggle("登录 Mac 时启动 Restling", isOn: Binding(
                get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                .accessibilityIdentifier("reminder.settings.loginItem")
            Text(loginItem.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(loginItem.requiresApproval ? Color.orange : muted)
                .fixedSize(horizontal: false, vertical: true)
            if loginItem.requiresApproval {
                Button("打开系统登录项设置") { loginItem.openSettings() }
                    .font(.system(size: 12))
            }
            note("此项修改立即生效。取消或关闭本窗口不会撤销系统登录项的变更。")
        }
    }

    private var scheduleExplanation: String {
        if !draft.scheduleEnabled { return "关闭限制后，提醒可在任意日期和时间运行。" }
        if draft.startMinute == draft.endMinute { return "开始与结束相同，表示所选日期全天可提醒。" }
        if draft.startMinute > draft.endMinute {
            return "跨午夜的时段归开始的那一天，例如周五 22:00 至周六 06:00 算周五。"
        }
        return "时段外不提醒。进入下一有效时段时，从新的用眼间隔开始。"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12, content: content)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        } label: {
            Text(title).font(.system(size: 13, weight: .semibold))
        }
    }

    private func choiceRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 18) {
            Text(title)
            Spacer(minLength: 12)
            content().labelsHidden().frame(width: 165)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func numberSetting(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        let bounded = Binding(get: { value.wrappedValue },
                              set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) })
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13))
            HStack(spacing: 7) {
                TextField(title, value: bounded, format: .number)
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .frame(width: 64).accessibilityLabel(title)
                Text(unit).font(.system(size: 12))
                Stepper(title, value: bounded, in: range).labelsHidden().fixedSize()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(get: { draft.weekdays.contains(day) }, set: { selected in
            if selected { draft.weekdays.insert(day) }
            else { draft.weekdays.remove(day) }
        })
    }

    private func clockBinding(_ keyPath: WritableKeyPath<ReminderPreferences, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = draft[keyPath: keyPath]
            // A time-of-day preference must remain editable even when today's
            // DST transition happens to skip the selected wall-clock time.
            let anchor = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15))
                ?? Date(timeIntervalSinceReferenceDate: 0)
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                                         second: 0, of: anchor) ?? anchor
        }, set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            draft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    private func save() {
        guard !hasEmptySchedule else { return }
        if pendingEyeRest != model.eyeRestSettings { model.applyEyeRestSettings(pendingEyeRest) }
        if draft != model.reminderPreferences { model.applyReminderPreferences(draft) }
        onClose()
    }
}
