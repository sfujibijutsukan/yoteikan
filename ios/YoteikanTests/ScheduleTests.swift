import XCTest
@testable import Yoteikan

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func testWidgetWindowIncludesRecentPastAndClampsToPlanningHours() {
        let now = date(29, 13, 17)
        let recent = ScheduleEvent(id: "past", title: "直前", start: date(29, 13), end: date(29, 13, 5), hex: "FFFFFF")
        let old = ScheduleEvent(id: "old", title: "範囲外", start: date(29, 12), end: date(29, 12, 30), hex: "FFFFFF")
        let future = ScheduleEvent(id: "next", title: "これから", start: date(29, 14, 30), end: date(29, 15), hex: "FFFFFF")
        let nextDay = ScheduleEvent(id: "tomorrow", title: "翌日", start: date(30, 9), end: date(30, 10), hex: "FFFFFF")
        let snapshot = ScheduleSnapshot(events: [recent, old, future, nextDay])
        let window = WidgetTimeWindow(snapshot: snapshot, now: now, calendar: calendar)
        XCTAssertEqual(window.start, date(29, 12, 47))
        XCTAssertEqual(window.end, date(29, 14, 47))
        XCTAssertEqual(window.events.map(\.id), ["past", "next"])
        XCTAssertEqual(window.currentPosition!, 0.25, accuracy: 0.001)
        let limited = ScheduleSnapshot(events: [], planningStart: 480, planningEnd: 600)
        let before = WidgetTimeWindow(snapshot: limited, now: date(29, 7), calendar: calendar)
        XCTAssertEqual(before.start, date(29, 8)); XCTAssertEqual(before.end, date(29, 10))
        XCTAssertNil(before.currentPosition)
        XCTAssertNil(WidgetTimeWindow(snapshot: limited, now: date(29, 10), calendar: calendar).currentPosition)
        let late = WidgetTimeWindow(snapshot: snapshot, now: date(29, 23, 55), calendar: calendar)
        XCTAssertEqual(late.start, date(29, 22)); XCTAssertEqual(late.end, date(30, 0))
        XCTAssertEqual(late.ticks(calendar: calendar).last, date(30, 0))
        XCTAssertTrue(WidgetTimeWindow(snapshot: snapshot, now: date(30, 0, 5), calendar: calendar).events.isEmpty)
    }
    func testWidgetShortAndSimultaneousNotesHaveReadableNonOverlappingRects() {
        let events = [
            ScheduleEvent(id: "a", title: "5分", start: date(29, 13), end: date(29, 13, 5), hex: "FFFFFF"),
            ScheduleEvent(id: "b", title: "次の5分", start: date(29, 13, 5), end: date(29, 13, 10), hex: "FFFFFF"),
            ScheduleEvent(id: "c", title: "同時", start: date(29, 13), end: date(29, 14), hex: "FFFFFF")
        ]
        let window = WidgetTimeWindow(snapshot: ScheduleSnapshot(events: events), now: date(29, 13), calendar: calendar)
        let cards = window.placements(height: 100)
        XCTAssertEqual(cards.count, 3)
        for card in cards {
            XCTAssertGreaterThanOrEqual(card.height, 20)
            XCTAssertGreaterThanOrEqual(card.y, 0)
            XCTAssertLessThanOrEqual(card.y + card.height, 100.001)
            XCTAssertLessThan(card.column, card.columns)
        }
        for a in cards { for b in cards where a.id < b.id {
            let horizontalOverlap = Double(a.column) / Double(a.columns) < Double(b.column + 1) / Double(b.columns) && Double(b.column) / Double(b.columns) < Double(a.column + 1) / Double(a.columns)
            let verticalOverlap = a.y < b.y + b.height && b.y < a.y + a.height
            XCTAssertFalse(horizontalOverlap && verticalOverlap)
        } }
        XCTAssertTrue(window.placements(height: 0).isEmpty)
    }
    func testWidgetTimelineTrimsOldAndDistantEventsWithoutDroppingSavedPlans() {
        let events = [28, 29, 30, 31].map { day in
            ScheduleEvent(id: String(day), title: "予定", start: date(day, 9), end: date(day, 10), hex: "FFFFFF")
        }
        let saved = ScheduleSnapshot(events: events, planningStart: 480, planningEnd: 1080)
        let trimmed = saved.timelineSnapshot(from: date(29, 13), calendar: calendar)
        XCTAssertEqual(trimmed.events.map(\.id), ["29", "30"])
        XCTAssertEqual(trimmed.planningStart, 480)
        XCTAssertEqual(trimmed.planningEnd, 1080)
        XCTAssertEqual(saved.events.count, 4)
        XCTAssertEqual(saved.timelineSnapshot(from: date(30, 13), calendar: calendar).events.map(\.id), ["30", "31"])
    }
    func testWidgetFiveMinuteTimelineCoversTomorrowAndReadsLegacySnapshot() throws {
        let snapshot = try JSONDecoder().decode(ScheduleSnapshot.self, from: Data("{\"version\":1,\"events\":[]}".utf8))
        XCTAssertNil(snapshot.planningStart)
        let now = date(29, 13, 17)
        let entries = snapshot.dates(from: now, calendar: calendar)
        XCTAssertEqual(entries.first, now)
        XCTAssertTrue(entries.contains(date(30, 0)))
        XCTAssertTrue(entries.contains(date(30, 13, 15)))
        XCTAssertEqual(entries, Array(Set(entries)).sorted())
        XCTAssertLessThanOrEqual(entries.count, 291)
        for entry in entries.dropFirst() {
            XCTAssertEqual(calendar.component(.minute, from: entry) % 5, 0)
            XCTAssertLessThanOrEqual(entry.timeIntervalSince(now), 86400)
        }
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
    let fixed = ScheduleEvent(id: "calendar-test", title: "固定会議", start: Date(), end: Date().addingTimeInterval(3600), hex: "E3E8E3")
    let withCalendar = WidgetPublisher.snapshot(for: plan, fixed: [fixed])
    XCTAssertTrue(withCalendar.events.contains(fixed))
    XCTAssertEqual(withCalendar.planningStart, plan.hours.start)
    XCTAssertEqual(withCalendar.planningEnd, plan.hours.end)
    XCTAssertFalse(String(decoding: try! JSONEncoder().encode(withCalendar), as: UTF8.self).contains("ウィジェットには渡さない"))
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
