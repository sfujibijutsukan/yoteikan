import XCTest
import UserNotifications

@testable import Yoteikan

@MainActor final class PlanTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() {
        super.setUp(); suite = "test.\(UUID())"; defaults = UserDefaults(suiteName: suite)!
        var manual = SavedPlan()
        for index in manual.presets.indices { manual.presets[index].dailyCount = 0 }
        defaults.set(try! JSONEncoder().encode(manual), forKey: "yoteikan.plan.v1")
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); super.tearDown() }
    func testCopyMakesIndependentUnplacedStickyAndPreservesOriginalAndUndo() throws {
        let store = PlanStore(defaults: defaults)
        store.add(Preset(title: "コピー元", minutes: 30, memo: "大切なメモ", dailyCount: 0))
        let id = try XCTUnwrap(store.today.first?.id)
        store.put(id, at: 600)
        let original = store.plan
        let copyID = try XCTUnwrap(store.duplicate(id))
        let copy = try XCTUnwrap(store.today.first { $0.id == copyID })
        XCTAssertNotEqual(copyID, id)
        XCTAssertNil(copy.start)
        XCTAssertEqual(copy.title, "コピー元")
        XCTAssertEqual(copy.memo, "大切なメモ")
        XCTAssertEqual(copy.minutes, 30)
        XCTAssertEqual(copy.reminderMinutes, original.stickies[0].reminderMinutes)
        XCTAssertEqual(store.today.first { $0.id == id }, original.stickies[0])
        XCTAssertEqual(PlanStore(defaults: defaults).plan, store.plan)
        store.restore()
        XCTAssertEqual(store.plan, original)
        store.put(id, at: nil)
        XCTAssertNotNil(store.duplicate(id))
        XCTAssertEqual(store.today.count, 2)
        XCTAssertTrue(store.today.allSatisfy { $0.start == nil })
    }
    func testNoOpKeepsUndoOfLastRealEdit() {
        let store = PlanStore(defaults: defaults)
        let before = store.plan
        store.add(Preset(title: "戻す", minutes: 30, dailyCount: 0))
        store.change { _ in }
        store.put(store.today[0].id, at: nil)
        XCTAssertEqual(store.undo, before)
        store.restore()
        XCTAssertEqual(store.plan, before)
        XCTAssertNil(store.undo)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, before)
    }
    func testFoldedTimelineInverseMapsDropsAcrossGapsAndEvents() {
        let folded = FoldedTimeline(items: [TimelineItem(id: "short", start: 480, end: 485),
                                           TimelineItem(id: "long", start: 600, end: 660)], start: 300, end: 1440)
        for minute in stride(from: 300, through: 1440, by: 5) {
            XCTAssertEqual(folded.minute(at: folded.position(minute)), CGFloat(minute), accuracy: 0.001)
        }
        XCTAssertEqual(folded.minute(at: -10), 300)
        XCTAssertEqual(folded.minute(at: folded.height + 10), 1440)
    }
    func testFoldedTimelineCompressesGapsAndKeepsShortOverlappingEventsReadable() {
        let events = [TimelineItem(id: "a", start: 480, end: 485), TimelineItem(id: "b", start: 485, end: 490), TimelineItem(id: "c", start: 482, end: 488)]
        let folded = FoldedTimeline(items: events, start: 300, end: 1440)
        XCTAssertEqual(folded.position(300), 0)
        XCTAssertEqual(folded.position(1440), folded.height)
        XCTAssertEqual(folded.bands.filter { !$0.occupied }.map(\.height), [32, 32])
        for event in events { XCTAssertGreaterThanOrEqual(folded.position(event.end) - folded.position(event.start), 44) }
        XCTAssertEqual(folded.position(485), folded.bands.first { $0.start == 485 }?.y)
        let dense = (0..<30).map { TimelineItem(id: "\($0)", start: 300 + $0 * 5, end: 305 + $0 * 5) }
        XCTAssertGreaterThan(FoldedTimeline(items: dense, start: 300, end: 1440).height, 1000)
    }
    func testMemoEditPreservesTimingAndOtherNotesAndSupportsUndo() {
        let store = PlanStore(defaults: defaults)
        store.add(store.plan.presets[0]); store.add(store.plan.presets[1])
        let id = store.today[0].id
        store.put(id, at: 600)
        let before = store.plan
        store.setMemo(id, memo: "次の章を読む")
        XCTAssertEqual(store.today[0].memo, "次の章を読む")
        XCTAssertEqual(store.today[0].start, 600)
        XCTAssertEqual(store.today[0].minutes, before.stickies[0].minutes)
        XCTAssertEqual(store.today[1], before.stickies[1])
        XCTAssertEqual(store.plan.presets, before.presets)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, store.plan)
        store.restore()
        XCTAssertEqual(store.plan, before)
    }
    func testLegacyPlanKeepsStickiesAndPresetsWhenAddingColorNames() throws {
        var old = SavedPlan()
        for index in old.presets.indices { old.presets[index].dailyCount = 0 }
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
    private func dailyStore(_ presets: [Preset]) throws -> PlanStore {
        var plan = SavedPlan(); plan.presets = presets
        defaults.set(try JSONEncoder().encode(plan), forKey: "yoteikan.plan.v1")
        return PlanStore(defaults: defaults)
    }
    func testDailyPresetCountsAreIndependentAndPersistAcrossDates() throws {
        let store = try dailyStore([
            Preset(title: "歯磨き", minutes: 5, tone: 2, memo: "朝と夜", dailyCount: 2),
            Preset(title: "ごはん", minutes: 30, dailyCount: 3),
            Preset(title: "任意", minutes: 10, dailyCount: 0)
        ])
        let today = store.date
        let original = store.today
        XCTAssertEqual(original.count, 5)
        XCTAssertEqual(Set(original.map(\.id)).count, 5)
        XCTAssertEqual(original.filter { $0.title == "歯磨き" }.count, 2)
        XCTAssertTrue(original.prefix(2).allSatisfy { $0.start == nil && $0.memo == "朝と夜" && $0.tone == 2 })
        store.prepareDay(); store.prepareDay()
        XCTAssertEqual(store.today, original)
        XCTAssertEqual(PlanStore(defaults: defaults).today, original)
        store.date = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        XCTAssertEqual(store.today.count, 5)
        XCTAssertTrue(Set(store.today.map(\.id)).isDisjoint(with: Set(original.map(\.id))))
        store.date = today
        XCTAssertEqual(store.today, original)
    }
    func testDailyPresetDoesNotRecreateMovedEditedDeletedOrManualCopies() throws {
        let store = try dailyStore([Preset(title: "歯磨き", minutes: 5, dailyCount: 2)])
        let id = store.today[0].id
        store.put(id, at: 600)
        store.setMemo(id, memo: "変更したメモ")
        var edited = store.today[0]; edited.minutes = 10; store.update(edited)
        store.remove(store.today[1].id)
        store.add(store.plan.presets[0])
        let expected = store.plan
        store.prepareDay()
        XCTAssertEqual(store.plan, expected)
        let restored = PlanStore(defaults: defaults)
        XCTAssertEqual(restored.plan, expected)
        XCTAssertEqual(restored.today.count, 2)
        XCTAssertEqual(restored.today[0].minutes, 10)
        XCTAssertEqual(restored.today[0].start, 600)
        XCTAssertEqual(restored.today[0].memo, "変更したメモ")
        store.remove(id); store.restore()
        XCTAssertEqual(store.plan, expected)
    }
    func testDailyCountChangesAddOnlyDeficitAndUndoTogether() throws {
        let store = try dailyStore([Preset(title: "ごはん", minutes: 30, dailyCount: 1)])
        let original = store.plan
        store.change { $0.presets[0].dailyCount = 3 }
        XCTAssertEqual(store.today.count, 3)
        store.restore()
        XCTAssertEqual(store.plan, original)
        store.change { $0.presets[0].dailyCount = 3 }
        let copies = store.today
        store.change { $0.presets[0].dailyCount = 1 }
        XCTAssertEqual(store.today, copies)
        store.change { $0.presets[0].dailyCount = 0 }
        XCTAssertEqual(store.today, copies)
        store.date = Calendar.current.date(byAdding: .day, value: 1, to: store.date)!
        XCTAssertTrue(store.today.isEmpty)
        store.change { $0.presets[0].dailyCount = 2 }
        XCTAssertEqual(store.today.count, 2)
        store.change { $0.presets.removeAll() }
        XCTAssertEqual(store.today.count, 2)
    }
    func testLegacyPresetsDefaultToOneAndDoNotDuplicateAfterMigration() throws {
        var old = SavedPlan()
        let day = dayKey(Date())
        old.stickies = [Sticky(title: "以前の予定", minutes: 30, day: day, start: 540)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        var presets = try XCTUnwrap(json["presets"] as? [[String: Any]])
        for index in presets.indices { presets[index].removeValue(forKey: "dailyCount") }
        json["presets"] = presets
        json.removeValue(forKey: "dailyPresetCounts")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "yoteikan.plan.v1")
        let store = PlanStore(defaults: defaults)
        XCTAssertTrue(store.plan.presets.allSatisfy { $0.dailyCount == 1 })
        XCTAssertEqual(store.today.count, 5)
        XCTAssertEqual(store.today.first, old.stickies.first)
        XCTAssertEqual(PlanStore(defaults: defaults).plan, store.plan)
        XCTAssertEqual(Preset(title: "範囲", minutes: 5, dailyCount: -1).dailyCount, 0)
        XCTAssertEqual(Preset(title: "範囲", minutes: 5, dailyCount: 999).dailyCount, 20)
    }
    func testDailyRefreshFollowsTodayButKeepsBrowsedDate() throws {
        let store = try dailyStore([Preset(title: "毎日", minutes: 5)])
        let today = store.date
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        store.refreshDay(now: tomorrow)
        XCTAssertEqual(dayKey(store.date), dayKey(tomorrow))
        XCTAssertEqual(store.today.count, 1)
        let notes = store.today
        store.refreshDay(now: tomorrow)
        XCTAssertEqual(store.today, notes)
        store.date = today
        store.refreshDay(now: Calendar.current.date(byAdding: .day, value: 1, to: tomorrow)!)
        XCTAssertEqual(dayKey(store.date), dayKey(today))
        XCTAssertEqual(store.today.count, 1)
    }
    func testSavingExistingStickyAsPresetCountsItForToday() throws {
        let store = try dailyStore([])
        let preset = Preset(title: "読書", minutes: 30, memo: "次の章")
        store.add(preset)
        store.change { $0.presets.append(preset); $0.markDailyPreset(preset.id, day: dayKey(store.date)) }
        XCTAssertEqual(store.today.count, 1)
        store.date = Calendar.current.date(byAdding: .day, value: 1, to: store.date)!
        XCTAssertEqual(store.today.count, 1)
        XCTAssertEqual(store.today[0].memo, "次の章")
    }
}

@MainActor private final class FakeReminderClient: ReminderClient {
    var authorization: UNAuthorizationStatus = .authorized
    var requests: [String: UNNotificationRequest] = [:]
    var fail = false
    func status() async -> UNAuthorizationStatus { authorization }
    func authorize() async throws -> Bool { authorization = .authorized; return true }
    func pending() async -> [UNNotificationRequest] { Array(requests.values) }
    func remove(_ ids: [String]) { ids.forEach { requests.removeValue(forKey: $0) } }
    func add(_ request: UNNotificationRequest) async throws {
        await Task.yield()
        if fail { throw NSError(domain: "test", code: 1) }
        requests[request.identifier] = request
    }
}
extension PlanTests {
    func testReminderLegacyDefaultOffAndCustomPersistWithUndo() throws {
        let original = Sticky(title: "通知", minutes: 30, day: "2030-01-02", start: 540)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "reminderMinutes")
        XCTAssertEqual(try JSONDecoder().decode(Sticky.self, from: JSONSerialization.data(withJSONObject: json)).reminderMinutes, 5)
        let store = PlanStore(defaults: defaults)
        var off = original; off.reminderMinutes = nil
        store.change { $0.stickies = [off] }
        XCTAssertNil(PlanStore(defaults: defaults).plan.stickies.first?.reminderMinutes)
        var custom = off; custom.reminderMinutes = 17
        store.update(custom)
        XCTAssertEqual(PlanStore(defaults: defaults).plan.stickies.first?.reminderMinutes, 17)
        store.restore()
        XCTAssertNil(store.plan.stickies.first?.reminderMinutes)
    }
    func testReminderDatesFilteringLimitAndSystemRequest() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 23))!
        var early = Sticky(title: "翌日の予定", minutes: 30, day: "2030-01-02", start: 3)
        early.reminderMinutes = 10
        var off = early; off.id = UUID(); off.reminderMinutes = nil
        var unplaced = early; unplaced.id = UUID(); unplaced.start = nil
        let past = Sticky(title: "過去", minutes: 30, day: "2030-01-01", start: 600)
        let later = Sticky(title: "後の予定", minutes: 30, day: "2030-01-02", start: 600)
        let results = PlannedReminder.upcoming([later, off, unplaced, past, early], now: now, calendar: calendar, limit: 1)
        let reminder = try XCTUnwrap(results.first)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(reminder.title, early.title)
        XCTAssertEqual(calendar.component(.day, from: reminder.fire), 1)
        XCTAssertEqual(calendar.component(.hour, from: reminder.fire), 23)
        XCTAssertEqual(calendar.component(.minute, from: reminder.fire), 53)
        let request = reminder.request(calendar: calendar)
        XCTAssertEqual(request.identifier, PlannedReminder.prefix + early.id.uuidString)
        XCTAssertEqual(request.content.title, early.title)
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual((request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(), reminder.fire)
    }
    func testReminderReconciliationMoveUnplaceDeleteDenyAndFailure() async throws {
        let client = FakeReminderClient()
        let store = ReminderStore(client: client, installDelegate: false)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        var task = Sticky(title: "通知", minutes: 30, day: dayKey(tomorrow), start: 540)
        store.update([task]); await store.waitUntilIdle()
        XCTAssertEqual(store.scheduled, 1)
        let old = try XCTUnwrap(client.requests.values.first?.trigger as? UNCalendarNotificationTrigger)
        task.start = 600; task.reminderMinutes = 17; task.title = "変更後"
        store.update([task]); await store.waitUntilIdle()
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertNotEqual((client.requests.values.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents, old.dateComponents)
        XCTAssertEqual(client.requests.values.first?.content.title, "変更後")
        var unplaced = task; unplaced.start = nil
        store.update([unplaced]); await store.waitUntilIdle(); XCTAssertEqual(store.scheduled, 0)
        store.update([task]); store.update([]); await store.waitUntilIdle(); XCTAssertEqual(store.scheduled, 0)
        store.update([task]); await store.waitUntilIdle()
        client.authorization = .denied
        store.update([task]); await store.waitUntilIdle(); XCTAssertEqual(store.scheduled, 0)
        client.authorization = .authorized; client.fail = true
        store.update([task]); await store.waitUntilIdle(); XCTAssertNotNil(store.message)
        client.fail = false
        store.update([task]); await store.waitUntilIdle(); XCTAssertEqual(store.scheduled, 1); XCTAssertNil(store.message)
        task.reminderMinutes = nil
        store.update([task]); await store.waitUntilIdle(); XCTAssertEqual(store.scheduled, 0)
    }
}
