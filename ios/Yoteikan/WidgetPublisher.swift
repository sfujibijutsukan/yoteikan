import Foundation
import WidgetKit

/// One worker owns file writes. A late, older update cannot replace a newer plan.
actor WidgetSnapshotWriter {
    private var latestRevision = 0
    func write(_ plan: SavedPlan, fixed: [ScheduleEvent], revision: Int, to url: URL?) throws -> Bool {
        guard revision > latestRevision else { return false }
        latestRevision = revision
        return try WidgetSnapshotStore.write(WidgetPublisher.snapshot(for: plan, fixed: fixed), to: url)
    }
}

@MainActor enum WidgetPublisher {
    private static let writer = WidgetSnapshotWriter()
    private static var revision = 0
    private static var pending: Task<Void, Never>?
    static func publish(_ plan: SavedPlan, demo: Bool, fixed: [ScheduleEvent] = []) {
        #if !targetEnvironment(macCatalyst)
        guard !demo else { return }
        revision += 1
        let next = revision
        pending?.cancel()
        pending = Task {
            // Collapse plan/calendar notifications from the same edit.
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            let url = WidgetSnapshotStore.fileURL()
            do {
                if try await writer.write(plan, fixed: fixed, revision: next, to: url) {
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
                }
            } catch {
                NSLog("Widget snapshot could not be updated: %@", error.localizedDescription)
            }
        }
        #endif
    }
    nonisolated static func snapshot(for plan: SavedPlan, fixed: [ScheduleEvent] = []) -> ScheduleSnapshot {
        let calendar = Calendar.current
        let palette = Dictionary(plan.colors.map { ($0.id, $0.hex) }, uniquingKeysWith: { first, _ in first })
        var days: [String: Date] = [:]
        let events = plan.stickies.compactMap { task -> ScheduleEvent? in
            guard let minute = task.start else { return nil }
            let day: Date
            if let cached = days[task.day] { day = cached }
            else {
                let parts = task.day.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3, let parsed = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
                days[task.day] = parsed; day = parsed
            }
            guard let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  let end = calendar.date(byAdding: .minute, value: task.minutes, to: start) else { return nil }
            return ScheduleEvent(id: task.id.uuidString, title: task.title, start: start, end: end,
                                 hex: palette[task.tone] ?? "E0EDCC")
        }
        return ScheduleSnapshot(events: (events + fixed).sorted { $0.id < $1.id }, planningStart: plan.hours.start, planningEnd: plan.hours.end)
    }
}
