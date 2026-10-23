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
struct SavedPlan: Codable, Equatable {
    static let defaultColorNames = ["準備", "仕事", "生活", "休憩"]
    var colorNames = defaultColorNames
    var stickies: [Sticky] = []
    var presets: [Preset] = [
        Preset(title: "読書", minutes: 30, tone: 0),
        Preset(title: "資料作成", minutes: 60, tone: 1),
        Preset(title: "運動", minutes: 20, tone: 2),
        Preset(title: "休憩", minutes: 15, tone: 3)
    ]
    init() {}
    private enum CodingKeys: String, CodingKey { case stickies, presets, colorNames }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stickies = try values.decodeIfPresent([Sticky].self, forKey: .stickies) ?? []
        presets = try values.decodeIfPresent([Preset].self, forKey: .presets) ?? presets
        colorNames = Self.normalizedColorNames(try values.decodeIfPresent([String].self, forKey: .colorNames) ?? Self.defaultColorNames)
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
    static let first = 6 * 60
    static let last = 24 * 60
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
    static func start(_ value: Int, duration: Int) -> Int { max(first, min(last - duration, value)) }
    static func duration(_ value: Int, start: Int) -> Int { max(5, min(720, last - start, value)) }
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
    func save() { if !demo, let data = try? JSONEncoder().encode(plan) { defaults.set(data, forKey: key) } }
    func change(_ body: (inout SavedPlan) -> Void) { undo = plan; body(&plan); save() }
    func restore() { guard let old = undo else { return }; plan = old; undo = nil; save() }
    func colorName(for tone: Int) -> String {
        plan.colorNames.indices.contains(tone) ? plan.colorNames[tone] : SavedPlan.defaultColorNames[0]
    }
    func setColorNames(_ names: [String]) {
        let normalized = SavedPlan.normalizedColorNames(names)
        guard normalized != plan.colorNames else { return }
        change { $0.colorNames = normalized }
    }
    func add(_ preset: Preset) {
        change { $0.stickies.append(Sticky(title: preset.title, minutes: preset.minutes, tone: preset.tone, memo: preset.memo, day: dayKey(date))) }
    }
    func put(_ id: UUID, at start: Int?) {
        guard let i = plan.stickies.firstIndex(where: { $0.id == id }) else { return }
        let duration = plan.stickies[i].minutes
        change { $0.stickies[i].start = start.map { PlannerMath.start($0, duration: duration) } }
    }
    func move(_ id: UUID, start: Int) { put(id, at: start) }
    func resize(_ id: UUID, minutes: Int) {
        guard let i = plan.stickies.firstIndex(where: { $0.id == id }), let start = plan.stickies[i].start else { return }
        change { $0.stickies[i].minutes = PlannerMath.duration(minutes, start: start) }
    }
    func update(_ task: Sticky) {
        guard let i = plan.stickies.firstIndex(where: { $0.id == task.id }) else { return }
        var task = task
        if let start = task.start { task.minutes = PlannerMath.duration(task.minutes, start: start) }
        change { $0.stickies[i] = task }
    }
    func remove(_ id: UUID) { change { $0.stickies.removeAll { $0.id == id } } }
}
