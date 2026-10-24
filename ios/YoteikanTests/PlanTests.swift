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
        json.removeValue(forKey: "colors")
        json["colorNames"] = ["朝", "集中", "生活", "休憩"]
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "yoteikan.plan.v1")
        let restored = PlanStore(defaults: defaults)
        XCTAssertEqual(restored.plan.stickies, old.stickies)
        XCTAssertEqual(restored.plan.presets, old.presets)
        XCTAssertEqual(restored.plan.colors.map(\.name), ["朝", "集中", "生活", "休憩"])
        json.removeValue(forKey: "colorNames")
        let original = try JSONDecoder().decode(SavedPlan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(original.colors, SavedPlan.defaultColors)
    }
    func testColorNamesPersistAndUndoWithoutChangingTasks() {
        let store = PlanStore(defaults: defaults)
        store.add(store.plan.presets[1])
        let before = store.plan
        var colors = store.plan.colors
        colors[1].name = "集中"; colors[1].hex = "ABCDEF"
        colors.append(StickyColor(id: 4, name: "趣味", hex: "DDDDEE"))
        store.setColors(colors, replacements: [:])
        XCTAssertEqual(store.plan.stickies, before.stickies)
        XCTAssertEqual(store.plan.presets, before.presets)
        XCTAssertEqual(PlanStore(defaults: defaults).plan.colors, colors)
        XCTAssertEqual(store.colorName(for: 1), "集中")
        store.restore()
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, before)
    }
    func testColorNamesNormalizeMissingBlankAndExtraEntries() throws {
        XCTAssertEqual(SavedPlan.normalizedColorNames(["", " 集中\n"]), ["準備", "集中", "生活", "休憩"])
        XCTAssertFalse(StickyColor.validHex("FFFF"))
        XCTAssertFalse(StickyColor.validHex("GGGGGG"))
        XCTAssertTrue(StickyColor.validHex("abcdef"))
        XCTAssertTrue(StickyColor(id: 0, name: "黒", hex: "000000").usesLightText)
        XCTAssertFalse(StickyColor(id: 0, name: "白", hex: "FFFFFF").usesLightText)
    }
    func testDeleteColorRemapsAllDaysAndPresetsAndUndoRestoresEverything() {
        let store = PlanStore(defaults: defaults)
        store.add(store.plan.presets[1])
        store.date = Calendar.current.date(byAdding: .day, value: 1, to: store.date)!
        store.add(store.plan.presets[1])
        store.add(store.plan.presets[2])
        let before = store.plan
        let colors = before.colors.filter { $0.id != 1 }
        store.setColors(colors, replacements: [1: 3])
        XCTAssertEqual(store.plan.stickies.map(\.tone), [3, 3, 2])
        XCTAssertEqual(store.plan.presets[1].tone, 3)
        XCTAssertEqual(store.plan.stickies.map(\.start), before.stickies.map(\.start))
        XCTAssertEqual(store.plan.stickies.map(\.minutes), before.stickies.map(\.minutes))
        XCTAssertEqual(PlanStore(defaults: defaults).plan, store.plan)
        store.restore()
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, before)
    }
    func testPaletteRejectsEmptyInvalidOrDuplicateColorsAndSupportsOneColor() {
        let store = PlanStore(defaults: defaults)
        let before = store.plan
        store.setColors([], replacements: [:])
        store.setColors([StickyColor(id: 0, name: " ", hex: "FFFFFF")], replacements: [:])
        store.setColors([StickyColor(id: 0, name: "色", hex: "X")], replacements: [:])
        store.setColors([before.colors[0], before.colors[0]], replacements: [:])
        XCTAssertEqual(store.plan, before)
        store.setColors([before.colors[3]], replacements: [0: 3, 1: 3, 2: 3])
        XCTAssertEqual(store.plan.colors.count, 1)
        XCTAssertTrue(store.plan.presets.allSatisfy { $0.tone == 3 })
        XCTAssertEqual(PlanStore(defaults: defaults).plan, store.plan)
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
        XCTAssertEqual(PlannerMath.start(100, duration: 30), 300)
        XCTAssertEqual(PlannerMath.duration(60, start: 1420), 20)
        XCTAssertEqual(PlannerMath.duration(-10, start: 600), 5)
        XCTAssertFalse(PlannerMath.overlaps(600, 630, 630, 660))
        XCTAssertTrue(PlannerMath.overlaps(600, 640, 630, 660))
        XCTAssertEqual(PlannerMath.occupied([(600, 660), (630, 700), (700, 720)]), 120)
        XCTAssertEqual(PlannerMath.occupied([(0, 500), (1400, 1600)]), 240)
    }

    func testFiveAMPlacementBoundsPersistenceAndUndo() {
        let store = PlanStore(defaults: defaults)
        store.add(Preset(title: "早朝の読書", minutes: 30))
        let id = store.today[0].id
        store.put(id, at: 300)
        XCTAssertEqual(store.today[0].start, 300)
        store.move(id, start: 240)
        XCTAssertEqual(store.today[0].start, 300)
        store.move(id, start: 1435)
        XCTAssertEqual(store.today[0].start, 1410)
        store.restore()
        XCTAssertEqual(store.today[0].start, 300)
        XCTAssertEqual(PlanStore(defaults: defaults).today[0].start, 300)
        store.resize(id, minutes: 60)
        XCTAssertEqual(store.today[0].start, 300)
        XCTAssertEqual(store.today[0].minutes, 60)
    }

    func testPlanningRangeIncludesEarlyCalendarTimeAndEndsAtMidnight() {
        XCTAssertEqual(PlannerMath.totalMinutes, 19 * 60)
        XCTAssertEqual(PlannerMath.occupied([]), 0)
        XCTAssertEqual(PlannerMath.occupied([(270, 330), (315, 360), (1430, 1500)]), 70)
        XCTAssertEqual(PlannerMath.totalMinutes - PlannerMath.occupied([(300, 330)]), 1110)
        XCTAssertEqual(PlannerMath.duration(60, start: 1420), 20)
        XCTAssertEqual(PlannerMath.start(300, duration: 720), 300)
    }

    func testCustomHoursPersistUndoAndPreserveAllPlans() {
        let store = PlanStore(defaults: defaults)
        store.add(store.plan.presets[0])
        store.put(store.today[0].id, at: 300)
        let before = store.plan
        store.setHours(PlanningHours(start: 480, end: 1200))
        XCTAssertEqual(store.plan.stickies, before.stickies)
        XCTAssertEqual(store.plan.presets, before.presets)
        XCTAssertEqual(store.hours.totalMinutes, 720)
        XCTAssertEqual(PlanStore(defaults: defaults).hours, store.hours)
        store.restore()
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, before)
    }

    func testCustomHoursConstrainPlacementAndRejectTooLongSticky() {
        let store = PlanStore(defaults: defaults)
        store.setHours(PlanningHours(start: 1200, end: 1320))
        store.add(Preset(title: "夜の読書", minutes: 30))
        let id = store.today[0].id
        store.put(id, at: 300)
        XCTAssertEqual(store.today[0].start, 1200)
        store.move(id, start: 1400)
        XCTAssertEqual(store.today[0].start, 1290)
        store.resize(id, minutes: 60)
        XCTAssertEqual(store.today[0].minutes, 30)
        store.add(Preset(title: "長い作業", minutes: 180))
        store.put(store.today[1].id, at: 1200)
        XCTAssertNil(store.today[1].start)
        XCTAssertEqual(store.today[1].minutes, 180)
        XCTAssertNotNil(store.notice)
        XCTAssertEqual(PlannerMath.occupied([(1140, 1230), (1300, 1400)], from: 1200, to: 1320), 50)
    }

    func testHoursMigrationAndInvalidSettingsKeepExistingData() throws {
        var old = SavedPlan()
        old.stickies = [Sticky(title: "既存の予定", minutes: 30, day: dayKey(Date()), start: 540)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "hours")
        var restored = try JSONDecoder().decode(SavedPlan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.hours, PlanningHours())
        XCTAssertEqual(restored.stickies, old.stickies)
        json["hours"] = ["start": 1200, "end": 600]
        restored = try JSONDecoder().decode(SavedPlan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.hours, PlanningHours())
        XCTAssertEqual(restored.stickies, old.stickies)
        let store = PlanStore(defaults: defaults)
        for hours in [PlanningHours(start: 600, end: 600), PlanningHours(start: -60, end: 1440),
                      PlanningHours(start: 0, end: 1500), PlanningHours(start: 301, end: 1440)] {
            store.setHours(hours)
            XCTAssertEqual(store.hours, PlanningHours())
        }
        store.setHours(PlanningHours(start: 0, end: 1440))
        XCTAssertEqual(store.hours.totalMinutes, 1440)
        store.setHours(PlanningHours(start: 1380, end: 1440))
        XCTAssertEqual(store.hours.totalMinutes, 60)
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
