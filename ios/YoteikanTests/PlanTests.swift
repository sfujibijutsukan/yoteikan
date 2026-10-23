import XCTest
@testable import Yoteikan

@MainActor final class PlanTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() { super.setUp(); suite = "test.\(UUID())"; defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); super.tearDown() }
    func testMovingOneStickyLeavesOthersAndPresetUnchanged() {
        let store = PlanStore(defaults: defaults)
        let preset = store.plan.presets[0]
        store.add(preset); store.add(preset)
        let ids = store.today.map(\.id)
        store.put(ids[0], at: 600); store.put(ids[1], at: 630)
        store.move(ids[0], start: 640)
        XCTAssertEqual(store.today[0].start, 640)
        XCTAssertEqual(store.today[1].start, 630)
        store.resize(ids[0], minutes: 45)
        XCTAssertEqual(store.today[0].minutes, 45)
        XCTAssertEqual(store.plan.presets[0].minutes, 30)
        XCTAssertEqual(store.today[1].start, 630)
    }
    func testUndoAndPersistenceAndUnplace() {
        let store = PlanStore(defaults: defaults); store.add(store.plan.presets[0])
        let id = store.today[0].id; store.put(id, at: 600); store.resize(id, minutes: 45); store.put(id, at: nil)
        XCTAssertNil(store.today[0].start); XCTAssertEqual(store.today[0].minutes, 45)
        store.restore(); XCTAssertEqual(store.today[0].start, 600)
        let restored = PlanStore(defaults: defaults)
        XCTAssertEqual(restored.plan, store.plan)
    }
    func testDateSeparationAndIndependentPresetCopies() {
        let store = PlanStore(defaults: defaults); store.add(store.plan.presets[0]); store.add(store.plan.presets[0])
        XCTAssertNotEqual(store.today[0].id, store.today[1].id)
        store.date = Calendar.current.date(byAdding: .day, value: 1, to: store.date)!
        XCTAssertTrue(store.today.isEmpty)
    }
    func testSnappingBoundsAndOverlapUnion() {
        XCTAssertEqual(PlannerMath.snap(608), 610)
        XCTAssertEqual(PlannerMath.start(1430, duration: 30), 1410)
        XCTAssertEqual(PlannerMath.start(100, duration: 30), 360)
        XCTAssertEqual(PlannerMath.duration(60, start: 1420), 20)
        XCTAssertEqual(PlannerMath.duration(-10, start: 600), 5)
        XCTAssertFalse(PlannerMath.overlaps(600, 630, 630, 660))
        XCTAssertTrue(PlannerMath.overlaps(600, 640, 630, 660))
        XCTAssertEqual(PlannerMath.occupied([(600, 660), (630, 700), (700, 720)]), 120)
        XCTAssertEqual(PlannerMath.occupied([(0, 500), (1400, 1600)]), 180)
    }

    func testOverlapColumnsCoverTransitiveGroupsAndReuseLanes() {
        let items = [TimelineItem(id: "a", start: 600, end: 660), TimelineItem(id: "b", start: 630, end: 690), TimelineItem(id: "c", start: 660, end: 720), TimelineItem(id: "d", start: 720, end: 750)]
        let slots = PlannerMath.layout(items)
        XCTAssertEqual(slots["a"]?.columns, 2)
        XCTAssertEqual(slots["c"]?.columns, 2)
        XCTAssertEqual(slots["a"]?.column, slots["c"]?.column)
        XCTAssertNotEqual(slots["b"]?.column, slots["c"]?.column)
        XCTAssertEqual(slots["d"]?.columns, 1)
    }
    func testThreeSimultaneousEventsHaveSeparateColumns() {
        let slots = PlannerMath.layout([TimelineItem(id: "a", start: 600, end: 660), TimelineItem(id: "b", start: 600, end: 660), TimelineItem(id: "c", start: 600, end: 630)])
        XCTAssertEqual(slots["a"]?.columns, 3)
        XCTAssertEqual(Set(slots.values.map(\.column)).count, 3)
    }
}
