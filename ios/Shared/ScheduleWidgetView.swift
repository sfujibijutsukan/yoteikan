import SwiftUI
import WidgetKit

struct ScheduleWidgetView: View {
    let date: Date
    let snapshot: ScheduleSnapshot?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var widgetFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    private var events: [ScheduleEvent] { snapshot?.events(on: date) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("予定館", systemImage: "note.text").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(date, format: .dateTime.month().day()).font(.caption2)
            }.foregroundStyle(colorScheme == .dark ? Color(red: 0.65, green: 0.83, blue: 0.73) : Color(red: 0.24, green: 0.40, blue: 0.33))
            if snapshot == nil {
                Spacer(minLength: 0)
                Text("アプリを開いて\n予定を読み込む").font(.subheadline)
                Spacer(minLength: 0)
            } else if let first = events.first {
                ForEach(Array(events.prefix(family == .systemSmall ? 1 : 3))) { event in
                    row(event)
                }
                if family == .systemSmall, let next = events.first(where: { $0.start > date }), first.id != next.id {
                    Text("次 \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)").font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("今日の予定はありません").font(.subheadline)
                Text("アプリで付箋を配置できます").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(colorScheme == .dark ? Color(red: 0.12, green: 0.17, blue: 0.15) : Color(red: 0.97, green: 0.96, blue: 0.93), for: .widget)
        .widgetURL(URL(string: "yoteikan://today"))
        .privacySensitive()
    }
    private func row(_ event: ScheduleEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color(event.hex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(event.start <= date ? "いま" : "次の予定").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }.lineLimit(1).minimumScaleFactor(0.8)
                Text(event.title).font(family == .systemSmall ? .headline : .subheadline.weight(.medium)).lineLimit(family == .systemSmall ? 2 : 1)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func color(_ hex: String) -> Color {
        let value = UInt(hex, radix: 16) ?? 0xE0EDCC
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
