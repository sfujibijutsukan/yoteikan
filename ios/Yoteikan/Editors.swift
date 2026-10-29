import SwiftUI
import UIKit

struct StickyEditor: View {
    @EnvironmentObject private var plans: PlanStore
    @EnvironmentObject private var reminders: ReminderStore
    @Environment(\.dismiss) private var dismiss
    @State var task: Sticky
    let isNew: Bool
    @State private var placed = false
    @State private var startTime = Date()
    @State private var saveAsPreset = false
    var body: some View {
        NavigationStack {
            Form {
                Section("やること") { TextField("例：読書", text: $task.title).accessibilityIdentifier("stickyTitle") }
                Section("所要時間") {
                    HStack { ForEach([15, 30, 45, 60], id: \.self) { minutes in Button { task.minutes = minutes } label: { Text("\(minutes)分").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10).background(task.minutes == minutes ? accent : paper, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(task.minutes == minutes ? .white : ink) }.buttonStyle(.plain).accessibilityIdentifier("duration-\(minutes)") } }
                    Stepper("\(task.minutes)分", value: $task.minutes, in: 5...720, step: 5).accessibilityIdentifier("durationStepper")
                }
                Section("色") { NamedColorPicker(selection: $task.tone) }
                Section {
                    Toggle("開始時刻を指定", isOn: $placed).accessibilityIdentifier("placeToggle")
                    if placed { DatePicker("開始", selection: $startTime, displayedComponents: .hourAndMinute).environment(\.locale, Locale(identifier: "ja_JP")) }
                } footer: { Text(plans.hours.label) }
                if placed && task.minutes > plans.hours.totalMinutes {
                    Section { Text("所要時間が計画の時間帯を超えています。").foregroundStyle(.orange) }
                }
                Section("通知") {
                    Toggle("開始前に通知", isOn: Binding(get: { task.reminderMinutes != nil }, set: { task.reminderMinutes = $0 ? 5 : nil }))
                        .accessibilityIdentifier("reminderToggle")
                    if task.reminderMinutes != nil {
                        Stepper(task.reminderMinutes == 0 ? "開始時刻に通知" : "\(task.reminderMinutes ?? 5)分前", value: Binding(get: { task.reminderMinutes ?? 5 }, set: { task.reminderMinutes = $0 }), in: 0...1440)
                            .accessibilityIdentifier("reminderMinutes")
                        if reminders.authorization == .notDetermined {
                            Button("通知を許可する") { Task { await reminders.enable() } }
                        } else if reminders.authorization == .denied {
                            Text("通知は許可されていません。設定画面から通知設定を開けます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("メモ") { TextField("任意", text: $task.memo, axis: .vertical).lineLimit(3...5).accessibilityIdentifier("stickyMemo") }
                if isNew { Section { Toggle("プリセットにも保存", isOn: $saveAsPreset) } }
                if !isNew {
                    Section {
                        Button("この付箋をプリセットに保存") { let preset = Preset(title: task.title, minutes: task.minutes, tone: task.tone, memo: task.memo); plans.change { $0.presets.append(preset); $0.markDailyPreset(preset.id, day: task.day) }; dismiss() }
                        Button("付箋を削除", role: .destructive) { plans.remove(task.id); dismiss() }.accessibilityIdentifier("deleteSticky")
                    }
                }
            }
            .scrollContentBackground(.hidden).background(paper)
            .navigationTitle(isNew ? "付箋をつくる" : "付箋を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold).disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (placed && task.minutes > plans.hours.totalMinutes)).accessibilityIdentifier("saveSticky") }
            }
            .onAppear {
                if !plans.plan.colors.contains(where: { $0.id == task.tone }) { task.tone = plans.plan.colors[0].id }
                placed = task.start != nil
                let start = task.start ?? 9 * 60
                startTime = Calendar.current.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: plans.date)!
            }
        }
    }
    private func save() {
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if placed { let parts = Calendar.current.dateComponents([.hour, .minute], from: startTime); task.start = PlannerMath.start(PlannerMath.snap(Double((parts.hour ?? 9) * 60 + (parts.minute ?? 0))), duration: task.minutes, from: plans.hours.start, to: plans.hours.end) }
        else { task.start = nil }
        if isNew {
            plans.change {
                $0.stickies.append(task)
                if saveAsPreset {
                    let preset = Preset(title: task.title, minutes: task.minutes, tone: task.tone, memo: task.memo)
                    $0.presets.append(preset); $0.markDailyPreset(preset.id, day: task.day)
                }
            }
        } else { plans.update(task) }
        dismiss()
    }
}

struct PlanningHoursEditor: View {
    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State var hours: PlanningHours
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("開始時刻", selection: $hours.start) {
                        ForEach(0..<(hours.end / 60), id: \.self) { hour in Text(clockText(hour * 60)).tag(hour * 60) }
                    }.accessibilityIdentifier("planningStart")
                    Picker("終了時刻", selection: $hours.end) {
                        ForEach((hours.start / 60 + 1)...24, id: \.self) { hour in Text(clockText(hour * 60)).tag(hour * 60) }
                    }.accessibilityIdentifier("planningEnd")
                }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("計画の時間帯").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.accessibilityIdentifier("cancelHours") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { plans.setHours(hours); dismiss() }.disabled(!hours.isValid).accessibilityIdentifier("saveHours")
                    }
                }
        }
    }
}

struct PresetsView: View {
    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var editing: Preset?
    @State private var added: [UUID: Int] = [:]
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(plans.plan.presets) { preset in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4).fill(plans.paletteColor(for: preset.tone).color).frame(width: 7, height: 42)
                            Button { plans.add(preset); added[preset.id, default: 0] += 1 } label: { HStack { VStack(alignment: .leading, spacing: 5) { Text(preset.title).font(.system(size: 16, weight: .medium)).foregroundStyle(ink); Text(durationText(preset.minutes)).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let count = added[preset.id] { Text("\(count)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(accent).accessibilityHidden(true) }; Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(accent) }.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("preset-\(preset.title)").accessibilityValue(added[preset.id].map { "\($0)枚追加済み" } ?? "")
                            Text(preset.dailyCount == 0 ? "自動なし" : "毎日\(preset.dailyCount)枚").font(.caption2).foregroundStyle(.secondary)
                            Button { editing = preset } label: { Image(systemName: "ellipsis").frame(width: 34, height: 44).foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("\(preset.title)のプリセットを編集").accessibilityIdentifier("edit-preset-\(preset.title)")
                        }.listRowBackground(Color.white)
                    }.onDelete { index in plans.change { $0.presets.remove(atOffsets: index) } }
                }
                Section { Button { creating = true } label: { Label("プリセットをつくる", systemImage: "plus") }.accessibilityIdentifier("newPreset") }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("プリセット").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.accessibilityIdentifier("closePresets") } }
                .sheet(isPresented: $creating) { PresetEditor(preset: Preset(title: "", minutes: 30), isNew: true) }
                .sheet(item: $editing) { PresetEditor(preset: $0, isNew: false) }
        }
    }
}
struct PresetEditor: View {
    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State var preset: Preset
    let isNew: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("名前") { TextField("例：読書", text: $preset.title).accessibilityIdentifier("presetTitle") }
                Section("所要時間") { Stepper("\(preset.minutes)分", value: $preset.minutes, in: 5...720, step: 5) }
                Section {
                    Stepper("毎日 \(preset.dailyCount)枚", value: $preset.dailyCount, in: 0...Preset.maximumDailyCount)
                        .accessibilityIdentifier("presetDailyCount")
                } header: { Text("毎日の自動追加") } footer: {
                    Text("その日の付箋置き場へ自動で追加します。0枚で停止。個数を増やすと今日の不足分も追加します。個数を減らしても、追加済みの付箋は残ります。")
                }
                Section("色") { NamedColorPicker(selection: $preset.tone) }
                Section("メモ") { TextField("任意", text: $preset.memo, axis: .vertical) }
                if !isNew { Section { Button("プリセットを削除", role: .destructive) { plans.change { $0.presets.removeAll { $0.id == preset.id } }; dismiss() } } }
            }.scrollContentBackground(.hidden).background(paper).navigationTitle(isNew ? "プリセットをつくる" : "プリセットを編集").navigationBarTitleDisplayMode(.inline)
                .onAppear { if !plans.plan.colors.contains(where: { $0.id == preset.tone }) { preset.tone = plans.plan.colors[0].id } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { preset.title = preset.title.trimmingCharacters(in: .whitespacesAndNewlines); plans.change { value in if isNew { value.presets.append(preset) } else if let i = value.presets.firstIndex(where: { $0.id == preset.id }) { value.presets[i] = preset } }; dismiss() }.disabled(preset.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("savePreset") }
                }
        }
    }
}

struct NamedColorPicker: View {
    @EnvironmentObject private var plans: PlanStore
    @Binding var selection: Int
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
            ForEach(plans.plan.colors) { color in
                Button { selection = color.id } label: {
                    VStack(spacing: 7) {
                        Circle().fill(color.color).frame(width: 36, height: 36)
                            .overlay { if selection == color.id { Image(systemName: "checkmark").foregroundStyle(ink).padding(3).background(.white.opacity(0.8), in: Circle()) } }
                        Text(color.name).font(.system(size: 12))
                            .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(ink)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("color-\(color.id)")
                    .accessibilityLabel(color.name)
                    .accessibilityValue(selection == color.id ? "選択中" : "")
            }
        }
    }
}

struct ColorNamesEditor: View {
    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State var colors: [StickyColor]
    @State private var replacements: [Int: Int] = [:]
    @State private var deleting: StickyColor?
    @State private var nextID = 0
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($colors) { $color in
                        VStack(spacing: 10) {
                            HStack(spacing: 14) {
                                ColorPicker("色", selection: Binding(get: { color.color }, set: { value in
                                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                                    UIColor(value).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                                    color.hex = String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
                                }), supportsOpacity: false).labelsHidden().accessibilityLabel("\(color.name)の色")
                                TextField("名前", text: $color.name)
                                    .accessibilityLabel("色\(color.id + 1)の名前").accessibilityIdentifier("color-name-\(color.id)")
                                Button(role: .destructive) { deleting = color } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                                    .buttonStyle(.borderless).disabled(colors.count == 1)
                                    .accessibilityLabel("\(color.name)を削除").accessibilityIdentifier("delete-color-\(color.id)")
                            }
                            HStack {
                                Text("#").foregroundStyle(.secondary)
                                TextField("RGB", text: $color.hex).font(.system(.caption, design: .monospaced))
                                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                    .accessibilityLabel("\(color.name)のカラーコード").accessibilityIdentifier("color-hex-\(color.id)")
                            }
                        }
                    }
                }
                Section {
                    Button { colors.append(StickyColor(id: nextID, name: "新しい色", hex: "E8DDF5")); nextID += 1 } label: {
                        Label("色を追加", systemImage: "plus")
                    }.accessibilityIdentifier("addColor")
                }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("付箋の色").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { plans.setColors(colors, replacements: replacements); dismiss() }
                            .disabled(colors.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !StickyColor.validHex($0.hex) })
                            .accessibilityIdentifier("saveColorNames")
                    }
                }
                .onAppear { nextID = max(nextID, (colors.map(\.id).max() ?? -1) + 1) }
                .confirmationDialog("削除後に使う色", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    if let source = deleting {
                        ForEach(colors.filter { $0.id != source.id }) { target in
                            Button("\(target.name)に付け替える") {
                                for key in Array(replacements.keys) where replacements[key] == source.id { replacements[key] = target.id }
                                replacements[source.id] = target.id
                                colors.removeAll { $0.id == source.id }
                                deleting = nil
                            }
                        }
                    }
                    Button("キャンセル", role: .cancel) { deleting = nil }
                } message: {
                    Text("この色の付箋とプリセットを、選んだ色に付け替えます。")
                }
        }
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var calendar: CalendarStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if calendar.connected {
                    Section {
                        if calendar.calendars.isEmpty { Text("カレンダーがありません").font(.subheadline) }
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                            Toggle(isOn: Binding(get: { calendar.enabled.contains(item.calendarIdentifier) }, set: { _ in calendar.toggle(item) })) { HStack { Circle().fill(Color(cgColor: item.cgColor)).frame(width: 10, height: 10); Text(item.title) } }.accessibilityIdentifier("calendar-\(item.title)")
                        }
                    } header: { Text("表示するカレンダー") } footer: { Text("読み込み専用") }
                } else {
                    Section { Button("カレンダーに接続") { Task { await calendar.connect() } }.accessibilityIdentifier("requestCalendar") } footer: { Text("読み込み専用です。iOSの許可画面ではフルアクセスが必要です。") }
                    Section { Button(PlatformSettings.calendarTitle) { if let url = PlatformSettings.calendarURL { UIApplication.shared.open(url) } } }
                }
                if let message = calendar.message { Section { Text(message).font(.subheadline).foregroundStyle(.orange) } }
            }.scrollContentBackground(.hidden).background(paper).navigationTitle("カレンダー").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.accessibilityIdentifier("closeCalendar") } }
        }
    }
}

enum PlannerSetting: String, Identifiable {
    case hours, colors, calendar, presets, stickies, newSticky, googleSync
    var id: String { rawValue }
}

struct PlannerSettingsFlow: View {
    @EnvironmentObject private var plans: PlanStore
    @State private var destination: PlannerSetting?
    @State private var editing: Sticky?
    init(initial: PlannerSetting? = nil) { _destination = State(initialValue: initial) }
    var body: some View {
        Group {
            if let task = editing { StickyEditor(task: task, isNew: false) }
            else if let destination {
                switch destination {
                case .googleSync: GoogleSyncView()
                case .hours: PlanningHoursEditor(hours: plans.hours)
                case .calendar: CalendarSettingsView()
                case .colors: ColorNamesEditor(colors: plans.plan.colors)
                case .presets: PresetsView()
                case .newSticky: StickyEditor(task: Sticky(title: "", minutes: 30, day: dayKey(plans.date)), isNew: true)
                case .stickies: SettingsStickyList { editing = $0 }
                }
            } else { PlannerSettingsView { destination = $0 } }
        }
    }
}

struct PlannerSettingsTab: View {
    let onFinished: () -> Void
    @State private var destination: PlannerSetting?
    var body: some View {
        PlannerSettingsView(open: { destination = $0 }, showsClose: false)
            .sheet(item: $destination, onDismiss: onFinished) { PlannerSettingsFlow(initial: $0) }
    }
}

struct PlannerSettingsView: View {
    let open: (PlannerSetting) -> Void
    var showsClose = true
    @AppStorage("planner.sidebarLeading") private var sidebarLeading = false
    @EnvironmentObject private var reminders: ReminderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var body: some View {
        NavigationStack {
            Form {
                Section { Button { open(.googleSync) } label: { Label("アカウント・同期", systemImage: "arrow.triangle.2.circlepath") }.accessibilityIdentifier("googleSyncSettings") }
                Section("時間・カレンダー") {
                    Button { open(.hours) } label: { Label("計画の時間帯", systemImage: "clock") }.accessibilityIdentifier("hoursSettings")
                    Button { open(.calendar) } label: { Label("カレンダー", systemImage: "calendar") }.accessibilityIdentifier("calendarSettings")
                }
                Section("付箋") {
                    Button { open(.stickies) } label: { Label("付箋を編集", systemImage: "square.and.pencil") }.accessibilityIdentifier("settingsEditStickies")
                    Button { open(.newSticky) } label: { Label("付箋をつくる", systemImage: "plus") }.accessibilityIdentifier("settingsNewSticky")
                    Button { open(.presets) } label: { Label("プリセット", systemImage: "square.stack") }.accessibilityIdentifier("settingsPresets")
                    Button { open(.colors) } label: { Label("付箋の色・名前", systemImage: "paintpalette") }.accessibilityIdentifier("colorSettings")
                }
                Section("サイドバーの位置") {
                    Picker("付箋・詳細", selection: $sidebarLeading) {
                        Text("左").tag(true)
                        Text("右").tag(false)
                    }.pickerStyle(.segmented).accessibilityIdentifier("sidebarPosition")
                }
                Section {
                    switch reminders.authorization {
                    case .notDetermined:
                        Button("通知を許可する") { Task { await reminders.enable() } }.accessibilityIdentifier("enableReminders")
                    case .denied:
                        Text("通知は許可されていません")
                        Button(PlatformSettings.notificationTitle) { if let url = PlatformSettings.notificationURL { openURL(url) } }
                    default:
                        Text("通知は許可されています")
                        Text("予約済み \(reminders.scheduled)件").accessibilityIdentifier("scheduledReminders")
                    }
                    if let message = reminders.message { Text(message).foregroundStyle(.orange) }
                } header: { Text("予定の通知") } footer: {
                    Text("配置した付箋は初期値5分前に通知します。付箋の編集画面で0〜1440分前、または通知なしに変更できます。直近60件を予約し、アプリを開いたときに更新します。未配置・通知時刻を過ぎた予定は通知しません。カレンダーの固定予定はカレンダー側の通知設定を使用します。")
                }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("アプリ設定").navigationBarTitleDisplayMode(.inline)
                .toolbar { if showsClose { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.accessibilityIdentifier("closePlannerSettings") } } }
        }
    }
}

struct SettingsStickyList: View {
    let select: (Sticky) -> Void
    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section(plans.date.formatted(.dateTime.month().day().weekday(.wide))) {
                    if plans.today.isEmpty { Text("この日の付箋はありません").foregroundStyle(.secondary) }
                    ForEach(plans.today.sorted { ($0.start ?? 1441) < ($1.start ?? 1441) }) { task in
                        Button { select(task) } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 3).fill(plans.paletteColor(for: task.tone).color).frame(width: 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).foregroundStyle(ink)
                                    Text(task.start.map { "\(clockText($0))〜\(clockText($0 + task.minutes))" } ?? "未配置・\(durationText(task.minutes))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("settingsSticky-\(task.title)")
                    }
                }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("付箋を編集").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.accessibilityIdentifier("closeSettingsStickies") } }
        }
    }
}

// Keep platform-specific settings links out of the planner flows.
enum PlatformSettings {
    #if targetEnvironment(macCatalyst)
    static let deviceName = "Mac"
    static let calendarTitle = "Macのカレンダー設定を開く"
    static let notificationTitle = "Macの通知設定を開く"
    static let calendarURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    static let notificationURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    #else
    static let deviceName = "iPhone"
    static let calendarTitle = "iPhoneの設定を開く"
    static let notificationTitle = "iPhoneの通知設定を開く"
    static let calendarURL = URL(string: UIApplication.openSettingsURLString)
    static let notificationURL = URL(string: UIApplication.openSettingsURLString)
    #endif
}
