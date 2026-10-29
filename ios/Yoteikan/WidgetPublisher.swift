import Foundation
import WidgetKit

@MainActor enum WidgetPublisher {
    static func publish(_ plan: SavedPlan, demo: Bool) {
        #if !targetEnvironment(macCatalyst)
        guard !demo else { return }
        do {
            if try WidgetSnapshotStore.write(snapshot(for: plan), to: WidgetSnapshotStore.fileURL()) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
            }
        } catch {
            NSLog("Widget snapshot could not be updated: %@", error.localizedDescription)
        }
        #endif
    }
    static func snapshot(for plan: SavedPlan) -> ScheduleSnapshot {
        let calendar = Calendar.current
        let events = plan.stickies.compactMap { task -> ScheduleEvent? in
            guard let minute = task.start else { return nil }
            let parts = task.day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  let end = calendar.date(byAdding: .minute, value: task.minutes, to: start) else { return nil }
            return ScheduleEvent(id: task.id.uuidString, title: task.title, start: start, end: end,
                                 hex: plan.colors.first { $0.id == task.tone }?.hex ?? "E0EDCC")
        }.sorted { $0.id < $1.id }
        return ScheduleSnapshot(events: events)
    }
}
