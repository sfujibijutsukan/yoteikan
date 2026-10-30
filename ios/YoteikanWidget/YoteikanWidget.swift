import WidgetKit
import SwiftUI

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleSnapshot?
}
struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry { sample() }
    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(context.isPreview ? sample() : ScheduleEntry(date: Date(), snapshot: WidgetSnapshotStore.read(from: WidgetSnapshotStore.fileURL())))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let date = Date()
        let snapshot = WidgetSnapshotStore.read(from: WidgetSnapshotStore.fileURL())?.timelineSnapshot(from: date)
        let dates = snapshot?.dates(from: date) ?? [date]
        completion(Timeline(entries: dates.map { ScheduleEntry(date: $0, snapshot: snapshot) },
                            policy: .after(date.addingTimeInterval(3600))))
    }
    private func sample() -> ScheduleEntry {
        let date = Date()
        return ScheduleEntry(date: date, snapshot: ScheduleSnapshot(events: [
            ScheduleEvent(id: "sample", title: "読書", start: date.addingTimeInterval(-300), end: date.addingTimeInterval(1500), hex: "E0EDCC")
        ]))
    }
}
@main struct YoteikanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(date: entry.date, snapshot: entry.snapshot)
        }
        .configurationDisplayName("今日の予定")
        .description("現在時刻前後の計画を時間割で確認できます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
