import XCTest
@testable import Yoteikan

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func testCurrentTimeOnlyAppearsTodayInsidePlanningRange() {
        let now = date(29, 13, 17)
        XCTAssertEqual(PlannerClock.minute(on: now, now: now, start: 300, end: 1440, calendar: calendar), 797)
        XCTAssertNil(PlannerClock.minute(on: date(28, 13), now: now, start: 300, end: 1440, calendar: calendar))
        XCTAssertNil(PlannerClock.minute(on: now, now: now, start: 840, end: 1440, calendar: calendar))
        XCTAssertNil(PlannerClock.minute(on: now, now: now, start: 300, end: 797, calendar: calendar))
        XCTAssertEqual(PlannerClock.focusMinute(on: now, now: now, start: 840, end: 1440, calendar: calendar), 840)
        XCTAssertEqual(PlannerClock.focusMinute(on: now, now: now, start: 300, end: 720, calendar: calendar), 719)
        XCTAssertEqual(PlannerClock.focusMinute(on: date(30, 8), now: now, start: 300, end: 1440, calendar: calendar), 480)
    }
    func testWidgetFiltersPastEventsAndSeparatesDaysAndOverlaps() {
        let a = ScheduleEvent(id: "a", title: "読書", start: date(29, 13), end: date(29, 14), hex: "E0EDCC")
        let b = ScheduleEvent(id: "b", title: "短い予定", start: date(29, 13, 15), end: date(29, 13, 20), hex: "DBE6F7")
        let tomorrow = ScheduleEvent(id: "c", title: "明日", start: date(30, 9), end: date(30, 10), hex: "E0EDCC")
        let snapshot = ScheduleSnapshot(events: [tomorrow, b, a])
        XCTAssertEqual(snapshot.events(on: date(29, 13, 17), calendar: calendar).map(\.id), ["a", "b"])
        XCTAssertEqual(snapshot.events(on: date(29, 13, 20), calendar: calendar).map(\.id), ["a"])
        XCTAssertTrue(snapshot.events(on: date(29, 14), calendar: calendar).isEmpty)
        XCTAssertEqual(snapshot.events(on: date(30, 8), calendar: calendar).map(\.id), ["c"])
        let dates = snapshot.dates(from: date(29, 13, 17), calendar: calendar)
        XCTAssertTrue(dates.contains(date(29, 13, 20)))
        XCTAssertTrue(dates.contains(date(29, 14)))
        XCTAssertTrue(dates.contains(date(30, 0)))
        XCTAssertEqual(dates, dates.sorted())
    }
    func testSharedSnapshotRoundTripRejectsUnknownVersionAndAvoidsRedundantReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = ScheduleSnapshot(events: [ScheduleEvent(id: "a", title: "日本語の予定", start: date(29, 13), end: date(29, 14), hex: "E0EDCC")])
        XCTAssertTrue(try WidgetSnapshotStore.write(snapshot, to: url))
        XCTAssertFalse(try WidgetSnapshotStore.write(snapshot, to: url))
        XCTAssertEqual(WidgetSnapshotStore.read(from: url), snapshot)
        var future = snapshot; future.version = 2
        try JSONEncoder().encode(future).write(to: url)
        XCTAssertNil(WidgetSnapshotStore.read(from: url))
        XCTAssertNil(WidgetSnapshotStore.read(from: nil))
        XCTAssertThrowsError(try WidgetSnapshotStore.write(snapshot, to: nil))
    }
@MainActor func testWidgetProjectionFollowsPlacementEditsAndRemoval() {
    var plan = SavedPlan(); plan.presets = []
    let placed = Sticky(title: "配置した予定", minutes: 5, tone: 1, memo: "ウィジェットには渡さない", day: dayKey(Date()), start: 797)
    plan.stickies = [placed, Sticky(title: "未配置", minutes: 30, day: dayKey(Date()))]
    let snapshot = WidgetPublisher.snapshot(for: plan)
    XCTAssertEqual(snapshot.events.count, 1)
    XCTAssertEqual(snapshot.events[0].title, placed.title)
    XCTAssertEqual(snapshot.events[0].hex, plan.colors[1].hex)
    XCTAssertEqual(snapshot.events[0].end.timeIntervalSince(snapshot.events[0].start), 300)
    plan.stickies[0].title = "編集した予定"
    XCTAssertEqual(WidgetPublisher.snapshot(for: plan).events[0].title, "編集した予定")
    plan.stickies[0].start = nil
    XCTAssertTrue(WidgetPublisher.snapshot(for: plan).events.isEmpty)
}

    func testFoldedCurrentTimePositionMatchesDropMapping() {
        let layout = FoldedTimeline(items: [TimelineItem(id: "short", start: 795, end: 800)], start: 300, end: 1440)
        XCTAssertEqual(layout.minute(at: layout.position(797)), 797, accuracy: 0.001)
    }
}
