import Foundation
import SwiftUI

struct Sticky: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var minutes: Int
    var tone: Int = 0
    var memo: String = ""
    var day: String
    var start: Int?
}
struct Preset: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var minutes: Int
    var tone: Int = 0
    var memo: String = ""
}
struct FixedEvent: Identifiable {
    var id: String
    var title: String
    var start: Int
    var end: Int
    var allDay = false
}
struct StickyColor: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var hex: String
    var color: Color {
        let value = UInt(hex, radix: 16) ?? 0xE0EDCC
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var usesLightText: Bool {
        let value = UInt(hex, radix: 16) ?? 0xE0EDCC
        func linear(_ channel: UInt) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((value >> 16) & 255) + 0.7152 * linear((value >> 8) & 255) + 0.0722 * linear(value & 255)
        let inkLuminance = 0.2126 * linear(41) + 0.7152 * linear(59) + 0.0722 * linear(54)
        return 1.05 / (luminance + 0.05) > (luminance + 0.05) / (inkLuminance + 0.05)
    }
    var textColor: Color { usesLightText ? .white : ink }
    static func validHex(_ text: String) -> Bool {
        text.count == 6 && text.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }
}
struct PlanningHours: Codable, Equatable {
    var start = 5 * 60
    var end = 24 * 60
    var isValid: Bool { start >= 0 && end <= 1440 && start < end && start % 60 == 0 && end % 60 == 0 }
    var totalMinutes: Int { end - start }
    var label: String { "\(start / 60):00〜\(end / 60):00" }
    func overlaps(start: Int, end: Int) -> Bool { start < self.end && end > self.start }
}
struct SavedPlan: Codable, Equatable {
    var hours = PlanningHours()
    static let defaultColorNames = ["準備", "仕事", "生活", "休憩"]
    static let defaultColors = zip(defaultColorNames, ["E0EDCC", "F7E3B3", "DBE6F7", "F5D9CF"]).enumerated().map {
        StickyColor(id: $0.offset, name: $0.element.0, hex: $0.element.1)
    }
    var colors = defaultColors
    var stickies: [Sticky] = []
    var presets: [Preset] = [
        Preset(title: "読書", minutes: 30, tone: 0),
        Preset(title: "資料作成", minutes: 60, tone: 1),
        Preset(title: "運動", minutes: 20, tone: 2),
        Preset(title: "休憩", minutes: 15, tone: 3)
    ]
    init() {}
    private enum CodingKeys: String, CodingKey { case stickies, presets, colorNames, colors, hours }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let saved = try values.decodeIfPresent(PlanningHours.self, forKey: .hours), saved.isValid { hours = saved }
        stickies = try values.decodeIfPresent([Sticky].self, forKey: .stickies) ?? []
        presets = try values.decodeIfPresent([Preset].self, forKey: .presets) ?? presets
        if let saved = try values.decodeIfPresent([StickyColor].self, forKey: .colors),
           !saved.isEmpty, Set(saved.map(\.id)).count == saved.count,
           saved.allSatisfy({ StickyColor.validHex($0.hex) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            colors = saved
        } else {
            let names = Self.normalizedColorNames(try values.decodeIfPresent([String].self, forKey: .colorNames) ?? Self.defaultColorNames)
            colors = Self.defaultColors.enumerated().map { index, color in
                var color = color; color.name = names[index]; return color
            }
        }
        let ids = Set(colors.map(\.id))
        for i in stickies.indices where !ids.contains(stickies[i].tone) { stickies[i].tone = colors[0].id }
        for i in presets.indices where !ids.contains(presets[i].tone) { presets[i].tone = colors[0].id }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(stickies, forKey: .stickies)
        try values.encode(presets, forKey: .presets)
        try values.encode(colors, forKey: .colors)
        try values.encode(hours, forKey: .hours)
    }
    static func normalizedColorNames(_ names: [String]) -> [String] {
        defaultColorNames.enumerated().map { index, fallback in
            guard names.indices.contains(index) else { return fallback }
            let name = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? fallback : name
        }
    }
}
struct TimelineItem {
    let id: String
    let start: Int
    let end: Int
}
struct TimelineSlot {
    let column: Int
    let columns: Int
}
enum PlannerMath {
    static let first = 5 * 60
    static let last = 24 * 60
    static let totalMinutes = last - first
    // Partition each connected overlap group into independent, consistent columns.
    static func layout(_ items: [TimelineItem]) -> [String: TimelineSlot] {
        let sorted = items.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var result: [String: TimelineSlot] = [:]
        var group: [(TimelineItem, Int)] = []
        var ends: [Int] = []
        var groupEnd = -1
        func finish() {
            for (item, column) in group { result[item.id] = TimelineSlot(column: column, columns: ends.count) }
        }
        for item in sorted {
            if item.start >= groupEnd { finish(); group = []; ends = []; groupEnd = -1 }
            let column = ends.firstIndex(where: { $0 <= item.start }) ?? ends.count
            if column == ends.count { ends.append(item.end) } else { ends[column] = item.end }
            group.append((item, column)); groupEnd = max(item.end, groupEnd)
        }
        finish()
        return result
    }
    static func snap(_ value: Double) -> Int { Int((value / 5).rounded()) * 5 }
    static func start(_ value: Int, duration: Int, from: Int = first, to: Int = last) -> Int { max(from, min(to - duration, value)) }
    static func duration(_ value: Int, start: Int, to: Int = last) -> Int { max(5, min(720, to - start, value)) }
    static func overlaps(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool { a < d && c < b }
    static func occupied(_ intervals: [(Int, Int)], from: Int = first, to: Int = last) -> Int {
        let sorted = intervals.map { (max(from, $0.0), min(to, $0.1)) }.filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var end = from, total = 0
        for item in sorted { total += max(0, item.1 - max(end, item.0)); end = max(end, item.1) }
        return total
    }
}
func clockText(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
func durationText(_ minute: Int) -> String {
    if minute < 60 { return "\(minute)分" }
    return minute % 60 == 0 ? "\(minute / 60)時間" : "\(minute / 60)時間\(minute % 60)分"
}
func dayKey(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
}
let ink = Color(red: 0.16, green: 0.23, blue: 0.21)
let accent = Color(red: 0.24, green: 0.40, blue: 0.33)
let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
let tones: [Color] = [Color(red: 0.88, green: 0.93, blue: 0.80), Color(red: 0.97, green: 0.89, blue: 0.70), Color(red: 0.86, green: 0.90, blue: 0.97), Color(red: 0.96, green: 0.85, blue: 0.81)]

@MainActor final class PlanStore: ObservableObject {
    @Published var plan: SavedPlan
    @Published var date = Date()
    @Published var undo: SavedPlan?
    @Published var notice: String?
    private let defaults: UserDefaults
    private let key = "yoteikan.plan.v1"
    let demo: Bool
    init(defaults: UserDefaults = .standard, demo: Bool = false) {
        self.defaults = defaults; self.demo = demo
        if demo {
            var sample = SavedPlan()
            let day = dayKey(Date())
            sample.stickies = [
                Sticky(title: "朝の読書", minutes: 30, tone: 0, memo: "気になる章をゆっくり読む", day: day, start: 8 * 60),
                Sticky(title: "資料作成", minutes: 60, tone: 1, day: day, start: 9 * 60),
                Sticky(title: "運動", minutes: 20, tone: 2, day: day),
                Sticky(title: "読書", minutes: 30, tone: 0, day: day),
                Sticky(title: "ひと休み", minutes: 15, tone: 3, day: day)
            ]
            plan = sample
        } else {
            plan = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedPlan.self, from: $0) } ?? SavedPlan()
        }
    }
    var today: [Sticky] { plan.stickies.filter { $0.day == dayKey(date) } }
    var hours: PlanningHours { plan.hours }
    func setHours(_ hours: PlanningHours) {
        guard hours.isValid, hours != plan.hours else { return }
        change { $0.hours = hours }
    }
    func save() { if !demo, let data = try? JSONEncoder().encode(plan) { defaults.set(data, forKey: key) } }
    func change(_ body: (inout SavedPlan) -> Void) { undo = plan; body(&plan); save() }
    func restore() { guard let old = undo else { return }; plan = old; undo = nil; save() }
    func colorName(for tone: Int) -> String {
        paletteColor(for: tone).name
    }
    func paletteColor(for tone: Int) -> StickyColor {
        plan.colors.first { $0.id == tone } ?? plan.colors[0]
    }
    func setColors(_ colors: [StickyColor], replacements: [Int: Int]) {
        guard !colors.isEmpty, Set(colors.map(\.id)).count == colors.count else { return }
        let normalized = colors.map { color in
            var color = color
            color.name = color.name.trimmingCharacters(in: .whitespacesAndNewlines)
            color.hex = color.hex.uppercased()
            return color
        }
        guard normalized.allSatisfy({ !$0.name.isEmpty && StickyColor.validHex($0.hex) }) else { return }
        let ids = Set(normalized.map(\.id))
        func replacement(_ tone: Int) -> Int {
            if ids.contains(tone) { return tone }
            if let target = replacements[tone], ids.contains(target) { return target }
            return normalized[0].id
        }
        guard normalized != plan.colors else { return }
        change {
            $0.colors = normalized
            for i in $0.stickies.indices { $0.stickies[i].tone = replacement($0.stickies[i].tone) }
            for i in $0.presets.indices { $0.presets[i].tone = replacement($0.presets[i].tone) }
        }
    }
    func add(_ preset: Preset) {
        change { $0.stickies.append(Sticky(title: preset.title, minutes: preset.minutes, tone: preset.tone, memo: preset.memo, day: dayKey(date))) }
    }
    func put(_ id: UUID, at start: Int?) {
        guard let i = plan.stickies.firstIndex(where: { $0.id == id }) else { return }
        let duration = plan.stickies[i].minutes
        guard start == nil || duration <= hours.totalMinutes else {
            notice = "この付箋を配置するには、所要時間を短くするか、計画の時間帯を広げてください。"
            return
        }
        change { $0.stickies[i].start = start.map { PlannerMath.start($0, duration: duration, from: hours.start, to: hours.end) } }
    }
    func move(_ id: UUID, start: Int) { put(id, at: start) }
    func resize(_ id: UUID, minutes: Int) {
        guard let i = plan.stickies.firstIndex(where: { $0.id == id }), let start = plan.stickies[i].start else { return }
        change { $0.stickies[i].minutes = PlannerMath.duration(minutes, start: start, to: hours.end) }
    }
    func update(_ task: Sticky) {
        guard let i = plan.stickies.firstIndex(where: { $0.id == task.id }) else { return }
        var task = task
        if let start = task.start { task.minutes = PlannerMath.duration(task.minutes, start: start, to: hours.end) }
        change { $0.stickies[i] = task }
    }
    func remove(_ id: UUID) { change { $0.stickies.removeAll { $0.id == id } } }
    func setMemo(_ id: UUID, memo: String) {
        guard let index = plan.stickies.firstIndex(where: { $0.id == id }), plan.stickies[index].memo != memo else { return }
        change { $0.stickies[index].memo = memo }
    }
}
