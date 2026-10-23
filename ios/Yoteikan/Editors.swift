import SwiftUI
import UIKit

struct StickyEditor: View {
    @EnvironmentObject private var plans: PlanStore
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
                } footer: { Text("6:00〜24:00") }
                Section("メモ") { TextField("任意", text: $task.memo, axis: .vertical).lineLimit(3...5).accessibilityIdentifier("stickyMemo") }
                if isNew { Section { Toggle("プリセットにも保存", isOn: $saveAsPreset) } }
                if !isNew {
                    Section {
                        Button("この付箋をプリセットに保存") { let preset = Preset(title: task.title, minutes: task.minutes, tone: task.tone, memo: task.memo); plans.change { $0.presets.append(preset) }; dismiss() }
                        Button("付箋を削除", role: .destructive) { plans.remove(task.id); dismiss() }.accessibilityIdentifier("deleteSticky")
                    }
                }
            }
            .scrollContentBackground(.hidden).background(paper)
            .navigationTitle(isNew ? "付箋をつくる" : "付箋を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold).disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveSticky") }
            }
            .onAppear {
                placed = task.start != nil
                let start = task.start ?? 9 * 60
                startTime = Calendar.current.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: plans.date)!
            }
        }
    }
    private func save() {
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if placed { let parts = Calendar.current.dateComponents([.hour, .minute], from: startTime); task.start = PlannerMath.start(PlannerMath.snap(Double((parts.hour ?? 9) * 60 + (parts.minute ?? 0))), duration: task.minutes) }
        else { task.start = nil }
        if isNew {
            plans.change {
                $0.stickies.append(task)
                if saveAsPreset { $0.presets.append(Preset(title: task.title, minutes: task.minutes, tone: task.tone, memo: task.memo)) }
            }
        } else { plans.update(task) }
        dismiss()
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
                            RoundedRectangle(cornerRadius: 4).fill(tones[preset.tone % tones.count]).frame(width: 7, height: 42)
                            Button { plans.add(preset); added[preset.id, default: 0] += 1 } label: { HStack { VStack(alignment: .leading, spacing: 5) { Text(preset.title).font(.system(size: 16, weight: .medium)).foregroundStyle(ink); Text(durationText(preset.minutes)).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let count = added[preset.id] { Text("\(count)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(accent).accessibilityHidden(true) }; Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(accent) }.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("preset-\(preset.title)").accessibilityValue(added[preset.id].map { "\($0)枚追加済み" } ?? "")
                            Button { editing = preset } label: { Image(systemName: "ellipsis").frame(width: 34, height: 44).foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("\(preset.title)のプリセットを編集")
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
                Section("色") { NamedColorPicker(selection: $preset.tone) }
                Section("メモ") { TextField("任意", text: $preset.memo, axis: .vertical) }
                if !isNew { Section { Button("プリセットを削除", role: .destructive) { plans.change { $0.presets.removeAll { $0.id == preset.id } }; dismiss() } } }
            }.scrollContentBackground(.hidden).background(paper).navigationTitle(isNew ? "プリセットをつくる" : "プリセットを編集").navigationBarTitleDisplayMode(.inline)
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
        HStack(spacing: 8) {
            ForEach(tones.indices, id: \.self) { index in
                Button { selection = index } label: {
                    VStack(spacing: 7) {
                        Circle().fill(tones[index]).frame(width: 36, height: 36)
                            .overlay { if selection == index { Image(systemName: "checkmark").foregroundStyle(ink) } }
                        Text(plans.colorName(for: index)).font(.system(size: 12))
                            .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(ink)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("color-\(index)")
                    .accessibilityLabel(plans.colorName(for: index))
                    .accessibilityValue(selection == index ? "選択中" : "")
            }
        }
    }
}

struct ColorNamesEditor: View {
    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State var names: [String]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(tones.indices, id: \.self) { index in
                        HStack(spacing: 14) {
                            Circle().fill(tones[index]).frame(width: 28, height: 28)
                            TextField(SavedPlan.defaultColorNames[index], text: $names[index])
                                .accessibilityLabel("色\(index + 1)の名前").accessibilityIdentifier("color-name-\(index)")
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("付箋の色").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { plans.setColorNames(names); dismiss() }
                            .disabled(names.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            .accessibilityIdentifier("saveColorNames")
                    }
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
                    Section { Button("iPhoneの設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                }
                if let message = calendar.message { Section { Text(message).font(.subheadline).foregroundStyle(.orange) } }
            }.scrollContentBackground(.hidden).background(paper).navigationTitle("カレンダー").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.accessibilityIdentifier("closeCalendar") } }
        }
    }
}
