import Foundation
import SwiftUI
import UserNotifications

struct Sticky: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var minutes: Int
    var tone: Int = 0
    var memo: String = ""
    var day: String
    var start: Int?
    var reminderMinutes: Int? = 5
}
extension Sticky {
    private enum CodingKeys: String, CodingKey { case id, title, minutes, tone, memo, day, start, reminderMinutes }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        minutes = try values.decode(Int.self, forKey: .minutes)
        tone = try values.decodeIfPresent(Int.self, forKey: .tone) ?? 0
        memo = try values.decodeIfPresent(String.self, forKey: .memo) ?? ""
        day = try values.decode(String.self, forKey: .day)
        start = try values.decodeIfPresent(Int.self, forKey: .start)
        reminderMinutes = values.contains(.reminderMinutes) ? try values.decodeIfPresent(Int.self, forKey: .reminderMinutes).map { min(1440, max(0, $0)) } : 5
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(title, forKey: .title)
        try values.encode(minutes, forKey: .minutes); try values.encode(tone, forKey: .tone)
        try values.encode(memo, forKey: .memo); try values.encode(day, forKey: .day)
        try values.encodeIfPresent(start, forKey: .start)
        // Explicit null distinguishes an intentional off setting from legacy data.
        try values.encode(reminderMinutes, forKey: .reminderMinutes)
    }
}

struct PlannedReminder: Equatable {
    let id: String
    let title: String
    let start: Date
    let fire: Date
    static let prefix = "yoteikan.sticky."
    static func upcoming(_ stickies: [Sticky], now: Date = Date(), calendar: Calendar = .current, limit: Int = 60) -> [PlannedReminder] {
        stickies.compactMap { task -> PlannedReminder? in
            guard let minute = task.start, (0..<1440).contains(minute), let lead = task.reminderMinutes, (0...1440).contains(lead) else { return nil }
            let parts = task.day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  let fire = calendar.date(byAdding: .minute, value: -lead, to: start), fire > now else { return nil }
            return PlannedReminder(id: prefix + task.id.uuidString, title: task.title, start: start, fire: fire)
        }.sorted { $0.fire == $1.fire ? $0.id < $1.id : $0.fire < $1.fire }.prefix(max(0, limit)).map { $0 }
    }
    func request(calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(start.formatted(date: .omitted, time: .shortened))からの予定です"
        content.sound = .default
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

@MainActor protocol ReminderClient {
    func status() async -> UNAuthorizationStatus
    func authorize() async throws -> Bool
    func pending() async -> [UNNotificationRequest]
    func remove(_ ids: [String])
    func add(_ request: UNNotificationRequest) async throws
}
@MainActor final class SystemReminderClient: ReminderClient {
    private let center = UNUserNotificationCenter.current()
    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func authorize() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pending() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func remove(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
}
@MainActor final class ReminderStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduled = 0
    @Published private(set) var message: String?
    private let client: any ReminderClient
    private var stickies: [Sticky] = []
    private var revision = 0
    private var worker: Task<Void, Never>?
    init(client: (any ReminderClient)? = nil, installDelegate: Bool = true) {
        self.client = client ?? SystemReminderClient()
        super.init()
        if installDelegate { UNUserNotificationCenter.current().delegate = self }
    }
    func update(_ stickies: [Sticky]) {
        self.stickies = stickies; revision += 1
        guard worker == nil else { return }
        worker = Task { await synchronize() }
    }
    func waitUntilIdle() async { await worker?.value }
    func enable() async {
        do { _ = try await client.authorize() } catch { message = "通知を許可できませんでした。もう一度お試しください。" }
        update(stickies)
        await waitUntilIdle()
    }
    // A single worker serializes changes so a slower old edit cannot restore stale requests.
    private func synchronize() async {
        var processed = -1
        while processed != revision {
            processed = revision
            let snapshot = stickies
            authorization = await client.status()
            let allowed = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
            let wanted = allowed ? PlannedReminder.upcoming(snapshot) : []
            let requests = wanted.map { $0.request() }
            let pending = await client.pending()
            let owned = pending.filter { $0.identifier.hasPrefix(PlannedReminder.prefix) }
            let ids = Set(requests.map(\.identifier))
            client.remove(owned.filter { !ids.contains($0.identifier) }.map(\.identifier))
            message = nil
            for request in requests {
                let existing = owned.first { $0.identifier == request.identifier }
                if existing?.content.title == request.content.title,
                   existing?.content.body == request.content.body,
                   (existing?.trigger as? UNCalendarNotificationTrigger)?.dateComponents == (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents { continue }
                do { try await client.add(request) }
                catch { message = "一部の通知を予約できませんでした。アプリを開き直してお試しください。" }
            }
            scheduled = await client.pending().filter { $0.identifier.hasPrefix(PlannedReminder.prefix) }.count
        }
        worker = nil
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}
struct Preset: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var minutes: Int
    var tone: Int = 0
    var memo: String = ""
    var dailyCount: Int = 1
    static let maximumDailyCount = 20
    init(id: UUID = UUID(), title: String, minutes: Int, tone: Int = 0, memo: String = "", dailyCount: Int = 1) {
        self.id = id; self.title = title; self.minutes = minutes; self.tone = tone; self.memo = memo
        self.dailyCount = min(Self.maximumDailyCount, max(0, dailyCount))
    }
    private enum CodingKeys: String, CodingKey { case id, title, minutes, tone, memo, dailyCount }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), title: try values.decode(String.self, forKey: .title),
                  minutes: try values.decode(Int.self, forKey: .minutes), tone: try values.decodeIfPresent(Int.self, forKey: .tone) ?? 0,
                  memo: try values.decodeIfPresent(String.self, forKey: .memo) ?? "",
                  dailyCount: try values.decodeIfPresent(Int.self, forKey: .dailyCount) ?? 1)
    }
}
struct FixedEvent: Identifiable {
    var id: String
    var title: String
    var start: Int
    var end: Int
    var allDay = false
    var memo: String = ""
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
    var dailyPresetCounts: [String: [String: Int]] = [:]
    var presets: [Preset] = [
        Preset(title: "読書", minutes: 30, tone: 0),
        Preset(title: "資料作成", minutes: 60, tone: 1),
        Preset(title: "運動", minutes: 20, tone: 2),
        Preset(title: "休憩", minutes: 15, tone: 3)
    ]
    init() {}
    private enum CodingKeys: String, CodingKey { case stickies, presets, colorNames, colors, hours, dailyPresetCounts }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let saved = try values.decodeIfPresent(PlanningHours.self, forKey: .hours), saved.isValid { hours = saved }
        stickies = try values.decodeIfPresent([Sticky].self, forKey: .stickies) ?? []
        presets = try values.decodeIfPresent([Preset].self, forKey: .presets) ?? presets
        dailyPresetCounts = try values.decodeIfPresent([String: [String: Int]].self, forKey: .dailyPresetCounts) ?? [:]
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
        try values.encode(dailyPresetCounts, forKey: .dailyPresetCounts)
    }
    @discardableResult mutating func populateDailyPresets(for day: String) -> Bool {
        var counts = dailyPresetCounts[day] ?? [:]
        var changed = false
        for preset in presets {
            let target = min(Preset.maximumDailyCount, max(0, preset.dailyCount))
            let generated = max(0, counts[preset.id.uuidString] ?? 0)
            guard target > generated else { continue }
            for index in generated..<target {
                let id = SyncCodec.dailyStickyID(preset: preset.id, day: day, index: index)
                if !stickies.contains(where: { $0.id == id }) {
                    stickies.append(Sticky(id: id, title: preset.title, minutes: preset.minutes, tone: preset.tone, memo: preset.memo, day: day))
                }
            }
            counts[preset.id.uuidString] = target
            changed = true
        }
        if changed { dailyPresetCounts[day] = counts }
        return changed
    }
    mutating func markDailyPreset(_ id: UUID, day: String) {
        dailyPresetCounts[day, default: [:]][id.uuidString] = 1
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
// A shared time mapping keeps overlapping cards aligned while compressing empty periods.
struct FoldedTimeline {
    struct Band {
        let start: Int
        let end: Int
        let occupied: Bool
        let y: CGFloat
        let height: CGFloat
    }
    let bands: [Band]
    var height: CGFloat { bands.last.map { $0.y + $0.height } ?? 0 }
    init(items: [TimelineItem], start: Int, end: Int) {
        let clipped = items.filter { $0.start < end && $0.end > start && $0.end > $0.start }
        let boundaries = Set([start, end] + clipped.flatMap { [max(start, $0.start), min(end, $0.end)] }).sorted()
        var result: [Band] = []
        var y: CGFloat = 0
        for (a, b) in zip(boundaries, boundaries.dropFirst()) {
            let occupied = clipped.contains { $0.start < b && $0.end > a }
            let height: CGFloat = occupied ? max(44, min(100, CGFloat(b - a))) : 32
            result.append(Band(start: a, end: b, occupied: occupied, y: y, height: height))
            y += height
        }
        bands = result
    }
    func position(_ minute: Int) -> CGFloat {
        guard let band = bands.first(where: { minute >= $0.start && minute < $0.end }) else {
            return minute <= (bands.first?.start ?? 0) ? 0 : height
        }
        return band.y + CGFloat(minute - band.start) / CGFloat(band.end - band.start) * band.height
    }
    func minute(at position: CGFloat) -> CGFloat {
        guard let band = bands.first(where: { position >= $0.y && position < $0.y + $0.height }) else {
            return CGFloat(position <= 0 ? (bands.first?.start ?? 0) : (bands.last?.end ?? 0))
        }
        return CGFloat(band.start) + (position - band.y) / band.height * CGFloat(band.end - band.start)
    }
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
    @Published var date = Date() { didSet { prepareDay() } }
    @Published var undo: SavedPlan?
    @Published var notice: String?
    private let defaults: UserDefaults
    private let key = "yoteikan.plan.v1"
    private var lastRealDay = dayKey(Date())
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
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--short-events-test") {
                sample.stickies = [
                    Sticky(title: "読書5分", minutes: 5, tone: 0, day: day, start: 480),
                    Sticky(title: "休憩5分", minutes: 5, tone: 1, day: day, start: 485),
                    Sticky(title: "確認5分", minutes: 5, tone: 2, day: day, start: 490)
                ]
            }
            #endif
            sample.dailyPresetCounts[day] = Dictionary(uniqueKeysWithValues: sample.presets.map { ($0.id.uuidString, $0.dailyCount) })
            plan = sample
        } else {
            plan = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedPlan.self, from: $0) } ?? SavedPlan()
        }
        prepareDay()
    }
    var today: [Sticky] { plan.stickies.filter { $0.day == dayKey(date) } }
    var hours: PlanningHours { plan.hours }
    func setHours(_ hours: PlanningHours) {
        guard hours.isValid, hours != plan.hours else { return }
        change { $0.hours = hours }
    }
    func acceptSyncedPlan(_ incoming: SavedPlan) {
        guard incoming != plan else { return }
        undo = nil; plan = incoming
        plan.populateDailyPresets(for: dayKey(date))
        save()
    }
    func save() { if !demo, let data = try? JSONEncoder().encode(plan) { defaults.set(data, forKey: key) } }
    func prepareDay() { if plan.populateDailyPresets(for: dayKey(date)) { save() } }
    func refreshDay(now: Date = Date()) {
        let current = dayKey(now)
        let followsToday = dayKey(date) == lastRealDay
        lastRealDay = current
        if followsToday && dayKey(date) != current { date = now } else { prepareDay() }
    }
    func change(_ body: (inout SavedPlan) -> Void) { undo = plan; body(&plan); plan.populateDailyPresets(for: dayKey(date)); save() }
    func restore() { guard let old = undo else { return }; plan = old; undo = nil; plan.populateDailyPresets(for: dayKey(date)); save() }
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
