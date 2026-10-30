import SwiftUI
import EventKit

@MainActor final class CalendarStore: ObservableObject {
    private let store = EKEventStore()
    @Published var events: [FixedEvent] = []
    @Published private(set) var widgetEvents: [ScheduleEvent] = []
    @Published var calendars: [EKCalendar] = []
    @Published var enabled: Set<String>
    @Published var connected = false
    @Published var message: String?
    private var observer: NSObjectProtocol?
    private var date = Date()
    init() {
        enabled = Set(UserDefaults.standard.stringArray(forKey: "calendar.enabled") ?? [])
        connected = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        #if DEBUG && targetEnvironment(simulator)
        if connected && ProcessInfo.processInfo.arguments.contains("--calendar-test") { try? seedCalendar() }
        #endif
        reload()
    }
    func connect() async {
        do {
            connected = try await store.requestFullAccessToEvents()
            if connected {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--calendar-test") { try seedCalendar() }
                #endif
                reload()
            } else { message = "カレンダーへのアクセスが許可されていません。設定画面から変更できます。" }
        } catch { message = "カレンダーを読み込めませんでした：\(error.localizedDescription)" }
    }
    func refresh(date: Date) { self.date = date; reload() }
    func toggle(_ calendar: EKCalendar) {
        if enabled.contains(calendar.calendarIdentifier) { enabled.remove(calendar.calendarIdentifier) } else { enabled.insert(calendar.calendarIdentifier) }
        UserDefaults.standard.set(Array(enabled), forKey: "calendar.enabled"); reload()
    }
    func reload() {
        connected = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard connected else { events = []; widgetEvents = []; return }
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        if UserDefaults.standard.object(forKey: "calendar.enabled") == nil {
            enabled = Set(calendars.map(\.calendarIdentifier)); UserDefaults.standard.set(Array(enabled), forKey: "calendar.enabled")
        }
        let selected = calendars.filter { enabled.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { events = []; widgetEvents = []; return }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        events = store.events(matching: predicate).map {
            FixedEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "予定", start: max(0, Int($0.startDate.timeIntervalSince(start) / 60)), end: min(1440, Int($0.endDate.timeIntervalSince(start) / 60)), allDay: $0.isAllDay, memo: $0.notes ?? "")
        }.sorted { $0.start < $1.start }
        // The widget always shows today, even while the user browses another date.
        let today = Calendar.current.startOfDay(for: Date())
        let widgetEnd = Calendar.current.date(byAdding: .day, value: 2, to: today)!
        let widgetPredicate = store.predicateForEvents(withStart: today, end: widgetEnd, calendars: selected)
        widgetEvents = store.events(matching: widgetPredicate).filter { !$0.isAllDay }.map { event in
            ScheduleEvent(id: "calendar-\(event.eventIdentifier ?? event.title ?? "event")-\(event.startDate.timeIntervalSince1970)",
                          title: event.title ?? "予定", start: event.startDate, end: event.endDate, hex: "E3E8E3")
        }.sorted { $0.id < $1.id }
    }
    #if DEBUG && targetEnvironment(simulator)
    private func seedCalendar() throws {
        let name = "予定館・動作確認用"
        let calendar: EKCalendar
        if let found = store.calendars(for: .event).first(where: { $0.title == name }) { calendar = found }
        else {
            calendar = EKCalendar(for: .event, eventStore: store); calendar.title = name
            calendar.source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) ?? store.sources.first
            try store.saveCalendar(calendar, commit: true)
        }
        let day = Calendar.current.startOfDay(for: Date())
        let predicate = store.predicateForEvents(withStart: day, end: day.addingTimeInterval(86400), calendars: [calendar])
        let existing = store.events(matching: predicate)
        if existing.isEmpty {
            for (title, hour, minutes) in [("チームミーティング", 10, 60), ("打ち合わせ", 14, 60)] {
                let event = EKEvent(eventStore: store); event.calendar = calendar; event.title = title
                event.startDate = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                event.endDate = event.startDate.addingTimeInterval(Double(minutes * 60)); try store.save(event, span: .thisEvent)
            }
        }
        let allDay = existing.first(where: { $0.title == "企画を考える日" }) ?? EKEvent(eventStore: store)
        allDay.calendar = calendar; allDay.title = "企画を考える日"; allDay.isAllDay = true
        // EventKit treats the end date of an all-day event as its final included day.
        allDay.startDate = day; allDay.endDate = day
        try store.save(allDay, span: .thisEvent)
        enabled.insert(calendar.calendarIdentifier); UserDefaults.standard.set(Array(enabled), forKey: "calendar.enabled")
    }
    #endif
}
