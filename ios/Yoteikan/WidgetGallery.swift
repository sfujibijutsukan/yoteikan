#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import WidgetKit

struct WidgetGallery: View {
    private let now = PlannerClock.now
    @State private var saved = false
    private var sample: ScheduleSnapshot { sample(at: now) }
    private func sample(at now: Date) -> ScheduleSnapshot {
        ScheduleSnapshot(events: [
            ScheduleEvent(id: "reading", title: "朝の読書", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(1500), hex: "E0EDCC"),
            ScheduleEvent(id: "work", title: "資料作成", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400), hex: "F7E3B3"),
            ScheduleEvent(id: "break", title: "ひと休み", start: now.addingTimeInterval(5700), end: now.addingTimeInterval(6600), hex: "F5D9CF")
        ])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ウィジェット表示の検証").font(.headline)
            Text("小サイズ").font(.caption)
            ScheduleWidgetView(date: now, snapshot: sample, familyOverride: .systemSmall)
                .padding(16).frame(width: 170, height: 170).background(paper, in: RoundedRectangle(cornerRadius: 22))
            Text("中サイズ").font(.caption)
            ScheduleWidgetView(date: now, snapshot: sample, familyOverride: .systemMedium)
                .padding(16).frame(width: 340, height: 170).background(paper, in: RoundedRectangle(cornerRadius: 22))
            if saved { Text("共有データ保存済み").accessibilityIdentifier("widgetFixtureSaved") }
            Text("拡張機能と同じViewを使用したサンプルです").font(.caption2).foregroundStyle(.secondary)
}
.task {
    guard ProcessInfo.processInfo.arguments.contains("--widget-publish-test") else { return }
    do {
        try WidgetSnapshotStore.write(sample(at: Date()), to: WidgetSnapshotStore.fileURL())
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
        saved = true
    } catch { saved = false }
}
        .padding(20).accessibilityElement(children: .contain).accessibilityIdentifier("widgetGallery")
    }
}
#endif
