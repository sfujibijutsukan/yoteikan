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
    func events(on date: Date, calendar: Calendar = .current) -> [ScheduleEvent] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.start < end && $0.end > start && $0.end > date }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    /// Precompute event boundaries and midnight, rather than relying on per-minute widget refreshes.
    func dates(from date: Date, calendar: Calendar = .current) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        let end = calendar.date(byAdding: .day, value: 1, to: date)!
        let boundaries = events.flatMap { [$0.start, $0.end] }.filter { $0 > date && $0 <= end }
        return Array(Set([date, midnight] + boundaries)).sorted().prefix(256).map { $0 }
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
