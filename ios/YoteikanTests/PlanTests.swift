import XCTest
@testable import Yoteikan

@MainActor final class PlanTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() { super.setUp(); suite = "test.\(UUID())"; defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); super.tearDown() }
    func testLegacyPlanKeepsStickiesAndPresetsWhenAddingColorNames() throws {
        var old = SavedPlan()
        old.stickies = [Sticky(title: "残す予定", minutes: 45, tone: 1, day: dayKey(Date()), start: 600)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "colorNames")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "yoteikan.plan.v1")
        let restored = PlanStore(defaults: defaults)
        XCTAssertEqual(restored.plan.stickies, old.stickies)
        XCTAssertEqual(restored.plan.presets, old.presets)
        XCTAssertEqual(restored.plan.colorNames, SavedPlan.defaultColorNames)
    }
    func testColorNamesPersistAndUndoWithoutChangingTasks() {
        let store = PlanStore(defaults: defaults)
        store.add(store.plan.presets[1])
        let before = store.plan
        store.setColorNames(["朝の準備", "集中", "暮らし", "休む"])
        XCTAssertEqual(store.plan.stickies, before.stickies)
        XCTAssertEqual(store.plan.presets, before.presets)
        XCTAssertEqual(PlanStore(defaults: defaults).plan.colorNames, ["朝の準備", "集中", "暮らし", "休む"])
        XCTAssertEqual(store.colorName(for: 1), "集中")
        store.restore()
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, before)
    }
    func testColorNamesNormalizeMissingBlankAndExtraEntries() throws {
        XCTAssertEqual(SavedPlan.normalizedColorNames(["", " 集中\n"]), ["準備", "集中", "生活", "休憩"])
        var plan = SavedPlan()
        plan.colorNames = ["朝", "昼", "夜", "休", "余分"]
        let restored = try JSONDecoder().decode(SavedPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.colorNames, ["朝", "昼", "夜", "休"])
    }
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
