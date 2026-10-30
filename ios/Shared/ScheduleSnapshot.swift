import Foundation

struct ScheduleEvent: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let hex: String
}

/// A read-only projection for the widget; memos and calendar permissions stay in the app.
struct ScheduleSnapshot: Codable, Equatable {
    var version = 1
    var events: [ScheduleEvent] = []
    var planningStart: Int? = nil
    var planningEnd: Int? = nil
    func events(on date: Date, calendar: Calendar = .current) -> [ScheduleEvent] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.start < end && $0.end > start && $0.end > date }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    /// Timeline entries need only these two days; keep the saved cache intact.
    func timelineSnapshot(from date: Date, calendar: Calendar = .current) -> ScheduleSnapshot {
        let first = calendar.startOfDay(for: date)
        let last = calendar.date(byAdding: .day, value: 2, to: first)!
        var copy = self
        copy.events = events.filter { $0.end > first && $0.start < last }
        return copy
    }
    /// Prepare 24 hours of five-minute views; WidgetKit controls actual delivery.
    func dates(from date: Date, calendar: Calendar = .current) -> [Date] {
        let end = date.addingTimeInterval(86400)
        let next = (date.timeIntervalSince1970 / 300).rounded(.down) * 300 + 300
        let regular = stride(from: next, through: end.timeIntervalSince1970, by: 300).map { Date(timeIntervalSince1970: $0) }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        return Array(Set([date, midnight] + regular)).filter { $0 <= end }.sorted()
    }
}

enum WidgetSnapshotStore {
    static let group = "group.org.sfuji.yoteikan"
    static let kind = "YoteikanSchedule"
    static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("schedule-widget-v1.json")
    }
    static func read(from url: URL?) -> ScheduleSnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data), snapshot.version == 1 else { return nil }
        return snapshot
    }
    @discardableResult static func write(_ snapshot: ScheduleSnapshot, to url: URL?) throws -> Bool {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        if read(from: url) == snapshot { return false }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}

enum PlannerClock {
    static var now: Date {
        #if DEBUG
        if ProcessInfo.processInfo.environment["YOTEIKAN_UI_TEST"] == "1" {
            let minute = ProcessInfo.processInfo.arguments.contains("--now-test") ? 13 * 60 + 17 : 8 * 60
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())!
        }
        #endif
        return Date()
    }
    static func minute(on date: Date, now: Date, start: Int, end: Int, calendar: Calendar = .current) -> Int? {
        guard calendar.isDate(date, inSameDayAs: now) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= start && minute < end ? minute : nil
    }
    static func focusMinute(on date: Date, now: Date, start: Int, end: Int, calendar: Calendar = .current) -> Int {
        guard calendar.isDate(date, inSameDayAs: now) else { return min(max(480, start), end - 1) }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return min(max((parts.hour ?? 0) * 60 + (parts.minute ?? 0), start), end - 1)
    }
}

/// A bounded slice of today's plan, shared by the app preview and the extension.
struct WidgetTimeWindow {
    let start: Date
    let end: Date
    let now: Date
    let events: [ScheduleEvent]
    init(snapshot: ScheduleSnapshot, now: Date, span: TimeInterval = 7200, calendar: Calendar = .current) {
        self.now = now
        let day = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let first = min(1380, max(0, snapshot.planningStart ?? 0))
        let last = min(1440, max(first + 60, snapshot.planningEnd ?? 1440))
        let lower = calendar.date(bySettingHour: first / 60, minute: first % 60, second: 0, of: day)!
        let upper = last == 1440 ? nextDay : calendar.date(bySettingHour: last / 60, minute: last % 60, second: 0, of: day)!
        let duration = min(max(60, span), upper.timeIntervalSince(lower))
        let windowStart = min(max(now.addingTimeInterval(-duration / 4), lower), upper.addingTimeInterval(-duration))
        let windowEnd = windowStart.addingTimeInterval(duration)
        start = windowStart; end = windowEnd
        events = snapshot.events.filter { $0.start < windowEnd && $0.end > windowStart && $0.end > $0.start }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    func position(_ date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
    }
    var currentPosition: Double? { now >= start && now < end ? position(now) : nil }
    func ticks(calendar: Calendar = .current) -> [Date] {
        var tick = calendar.dateInterval(of: .hour, for: start)!.start
        var result: [Date] = []
        while tick <= end {
            if tick >= start { result.append(tick) }
            tick = tick.addingTimeInterval(1800)
        }
        return result
    }
    struct Placement: Identifiable {
        let event: ScheduleEvent
        let y: Double
        let height: Double
        let column: Int
        var columns: Int
        var id: String { event.id }
    }
    /// Short notes get readable heights; visual overlaps use separate columns.
    func placements(height: Double, minimumHeight: Double = 20) -> [Placement] {
        guard height > 0 else { return [] }
        let minimum = min(height, max(1, minimumHeight))
        let cards: [(event: ScheduleEvent, y: Double, height: Double)] = events.map { event -> (event: ScheduleEvent, y: Double, height: Double) in
            let y = min(height - minimum, position(event.start) * height)
            return (event: event, y: y, height: max(minimum, position(event.end) * height - y))
        }.sorted { a, b in a.y == b.y ? a.event.id < b.event.id : a.y < b.y }
        var result: [Placement] = [], group: [Placement] = []
        var lanes: [Double] = [], groupEnd = -Double.infinity
        func flush() {
            result += group.map { card in var copy = card; copy.columns = lanes.count; return copy }
            group.removeAll(); lanes.removeAll(); groupEnd = -Double.infinity
        }
        for (event, y, cardHeight) in cards {
            if y >= groupEnd { flush() }
            let lane = lanes.firstIndex(where: { $0 <= y }) ?? lanes.count
            if lane == lanes.count { lanes.append(y + cardHeight) } else { lanes[lane] = y + cardHeight }
            group.append(Placement(event: event, y: y, height: cardHeight, column: lane, columns: 1))
            groupEnd = max(groupEnd, y + cardHeight)
        }
        flush()
        return result
    }
}
