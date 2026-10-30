import SwiftUI
import WidgetKit

struct ScheduleWidgetView: View {
    let date: Date
    let snapshot: ScheduleSnapshot?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var widgetFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    private var ink: Color { colorScheme == .dark ? .white : Color(red: 0.16, green: 0.23, blue: 0.20) }
    private var accent: Color { colorScheme == .dark ? Color(red: 0.65, green: 0.83, blue: 0.73) : Color(red: 0.24, green: 0.40, blue: 0.33) }
    private func clock(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "ja_JP"))) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "calendar.day.timeline.left")
                Text(date, format: .dateTime.month().day().weekday(.abbreviated)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            if let snapshot {
                timeline(WidgetTimeWindow(snapshot: snapshot, now: date, span: family == .systemSmall ? 3600 : 7200))
            } else {
                Spacer(minLength: 0)
                Text("アプリを開いて\n予定を読み込む").font(.subheadline)
                Spacer(minLength: 0)
            }
        }.foregroundStyle(ink)
        .containerBackground(colorScheme == .dark ? Color(red: 0.12, green: 0.17, blue: 0.15) : Color(red: 0.97, green: 0.96, blue: 0.93), for: .widget)
        .widgetURL(URL(string: "yoteikan://today"))
        .privacySensitive()
    }
    private func timeline(_ window: WidgetTimeWindow) -> some View {
        GeometryReader { geometry in
            let gutter: CGFloat = 36
            let height = max(0, geometry.size.height - 12)
            ZStack(alignment: .topLeading) {
                ForEach(window.ticks(), id: \.self) { tick in
                    HStack(spacing: 4) {
                        Text(clock(tick)).font(.system(size: 9, weight: .medium, design: .monospaced))
                            .frame(width: gutter - 4, alignment: .trailing)
                        Rectangle().frame(height: 0.5)
                    }.foregroundStyle(ink.opacity(0.4)).frame(height: 12)
                        .offset(y: window.position(tick) * height)
                }
                ForEach(window.placements(height: height)) { placement in
                    let width = max(0, geometry.size.width - gutter) / CGFloat(placement.columns)
                    let event = placement.event
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.system(size: family == .systemSmall ? 10 : 12, weight: .semibold))
                            .lineLimit(placement.height >= 34 ? 2 : 1).minimumScaleFactor(0.8)
                        if family == .systemMedium && placement.height >= 46 && width >= 88 {
                            Text("\(clock(event.start))–\(clock(event.end))").font(.system(size: 8)).monospacedDigit().lineLimit(1)
                        }
                    }.padding(.horizontal, 4).padding(.vertical, 2)
                        .frame(width: max(0, width - 2), height: placement.height, alignment: .topLeading)
                        .foregroundStyle(textColor(event.hex))
                        .background(color(event.hex), in: RoundedRectangle(cornerRadius: 3))
                        .overlay(alignment: .leading) { Rectangle().fill(textColor(event.hex).opacity(0.25)).frame(width: 2) }
                        .opacity(event.end <= date ? 0.6 : 1).clipped()
                        .offset(x: gutter + width * CGFloat(placement.column), y: placement.y + 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(clock(event.start))〜\(clock(event.end))、\(event.title)")
                }
                if window.events.isEmpty {
                    Text("この時間帯の\n予定はありません").font(.system(size: 11)).multilineTextAlignment(.center)
                        .foregroundStyle(ink.opacity(0.65)).frame(width: max(0, geometry.size.width - gutter))
                        .offset(x: gutter, y: height * 0.55)
                }
                if let position = window.currentPosition {
                    HStack(spacing: 0) {
                        Text(clock(date)).font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white).frame(width: gutter - 4, height: 12).background(.red, in: Capsule())
                        Circle().fill(.red).frame(width: 4, height: 4)
                        Rectangle().fill(.red).frame(height: 1)
                    }.frame(height: 12).offset(y: position * height)
                        .accessibilityElement(children: .ignore).accessibilityLabel("現在時刻 \(clock(date))")
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped().accessibilityElement(children: .contain).accessibilityIdentifier("widgetPlanTimeline")
        }
    }
    private func components(_ hex: String) -> (Double, Double, Double) {
        let value = UInt(hex, radix: 16) ?? 0xE0EDCC
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
    private func color(_ hex: String) -> Color {
        let (r, g, b) = components(hex)
        return Color(red: r, green: g, blue: b)
    }
    private func textColor(_ hex: String) -> Color {
        let (r, g, b) = components(hex)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.55 ? Color(red: 0.16, green: 0.23, blue: 0.20) : .white
    }
}
