import XCTest

final class YoteikanUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    func launch(_ args: [String] = ["--demo"]) { app = XCUIApplication(); app.launchArguments = args; app.launch(); XCTAssertTrue(app.buttons["presetsButton"].waitForExistence(timeout: 10)) }
    func shot(_ name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
    func test01DemoAndPresets() {
        launch(); shot("01-day-planner")
        app.buttons["presetsButton"].tap()
        XCTAssertTrue(app.buttons["preset-読書"].waitForExistence(timeout: 3)); app.buttons["preset-読書"].tap()
        XCTAssertEqual(app.buttons["preset-読書"].value as? String, "1枚追加済み"); shot("02-presets")
        app.buttons["closePresets"].tap()
        XCTAssertEqual(app.otherElements.matching(identifier: "inbox-読書").count, 2)
    }
    func test02CreatePersistEditAndUndo() {
        launch(["--reset-test-data"])
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap(); app.textFields["stickyTitle"].typeText("集中作業")
        app.buttons["duration-45"].tap(); app.buttons["saveSticky"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-集中作業").firstMatch.waitForExistence(timeout: 3))
        app.terminate(); launch([])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-集中作業").firstMatch.exists)
        app.descendants(matching: .any).matching(identifier: "inbox-集中作業").firstMatch.tap(); app.buttons["duration-60"].tap(); app.buttons["saveSticky"].tap()
        app.buttons["undoButton"].tap()
        app.descendants(matching: .any).matching(identifier: "inbox-集中作業").firstMatch.tap()
        XCTAssertTrue(app.steppers["durationStepper"].label.contains("45")); shot("03-sticky-editor")
    }
    func test03DragResizeAndUnplace() {
        launch()
        let task = app.otherElements["task-資料作成"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        let from = task.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.30))
        from.press(forDuration: 0.5, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 46.5)))
        XCTAssertEqual(task.value as? String, "09:30|60")
        XCTAssertEqual(app.otherElements["task-朝の読書"].value as? String, "08:00|30")
        shot("04-overlap-after-drag")
        app.buttons["undoButton"].tap()
        let handle = app.otherElements["resize-資料作成"]
        XCTAssertTrue(handle.exists)
        let point = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(forDuration: 0.15, thenDragTo: point.withOffset(CGVector(dx: 0, dy: 46.5)))
        XCTAssertEqual(task.value as? String, "09:00|90")
        shot("05-resize-overlap")
        app.buttons["unplaceButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-資料作成").firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["task-資料作成"].exists)
        app.buttons["undoButton"].tap()
        XCTAssertTrue(app.otherElements["task-資料作成"].exists)
        let returnFrom = task.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let tray = app.otherElements["inboxTray"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        returnFrom.press(forDuration: 0.5, thenDragTo: tray)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-資料作成").firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["task-資料作成"].exists)
    }
    func test04InboxDropAndOverview() {
        launch()
        let card = app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch
        let timeline = app.scrollViews["timeline"]
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.2)))
        XCTAssertTrue(app.otherElements["task-運動"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch.exists)
        app.buttons["zoomToggle"].tap(); Thread.sleep(forTimeInterval: 0.8); shot("06-day-overview")
    }
    func test05CalendarAccessAndRealEventKitRead() {
        launch(["--calendar-test"])
        app.buttons["calendarSettings"].tap()
        if app.buttons["requestCalendar"].exists {
            app.buttons["requestCalendar"].tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label CONTAINS 'フルアクセス' OR label == 'Allow'")).firstMatch
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
        XCTAssertTrue(app.switches["calendar-予定館・動作確認用"].firstMatch.waitForExistence(timeout: 8))
        shot("07-calendar-settings")
        app.buttons["closeCalendar"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fixed-チームミーティング").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["企画を考える日"].exists)
        shot("08-real-calendar-events")
    }

    func test06CreatePresetAndReuseItToday() {
        launch()
        app.buttons["presetsButton"].tap(); app.buttons["newPreset"].tap()
        app.textFields["presetTitle"].tap(); app.textFields["presetTitle"].typeText("散歩")
        app.buttons["savePreset"].tap()
        XCTAssertTrue(app.buttons["preset-散歩"].waitForExistence(timeout: 3))
        app.buttons["preset-散歩"].tap(); app.buttons["closePresets"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-散歩").firstMatch.exists)
        app.buttons["次の日"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "inbox-散歩").firstMatch.exists)
        app.buttons["todayButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-散歩").firstMatch.exists)
    }
    func test07CalendarSelectionChangesVisibleEvents() {
        launch(["--calendar-test"])
        app.buttons["calendarSettings"].tap()
        let toggle = app.switches["calendar-予定館・動作確認用"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["closeCalendar"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "fixed-チームミーティング").firstMatch.exists)
        app.buttons["calendarSettings"].tap(); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); app.buttons["closeCalendar"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fixed-チームミーティング").firstMatch.waitForExistence(timeout: 3))
    }

    private func createAndPlaceSticky() -> XCUIElement {
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("移動の確認")
        app.buttons["duration-60"].tap()
        app.buttons["saveSticky"].tap()
        let inbox = app.descendants(matching: .any).matching(identifier: "inbox-移動の確認").firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        let target = app.scrollViews["timeline"].coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4))
        inbox.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: target)
        let task = app.otherElements["task-移動の確認"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        return task
    }
    private func placement(of task: XCUIElement) -> (start: Int, duration: Int) {
        let fields = (task.value as? String ?? "").split(separator: "|")
        XCTAssertEqual(fields.count, 2)
        guard fields.count == 2 else { return (-1, -1) }
        let clock = fields[0].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2, let duration = Int(fields[1]) else { XCTFail("Missing placement value"); return (-1, -1) }
        return (clock[0] * 60 + clock[1], duration)
    }
    func test08NewlyPlacedStickyMovesFromEmptyBodyArea() {
        launch(["--reset-test-data"])
        let task = createAndPlaceSticky()
        let before = placement(of: task)
        let point = task.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6))
        point.press(forDuration: 0.5, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -46.5)))
        let after = placement(of: task)
        XCTAssertEqual(after.start, before.start - 30)
        XCTAssertEqual(after.duration, 60)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "inbox-移動の確認").firstMatch.exists)
    }
    func test09MoveHandleChangesStartAndPersistsWithUndo() {
        launch(["--reset-test-data"])
        let task = createAndPlaceSticky()
        let before = placement(of: task)
        let handle = app.otherElements["move-移動の確認"]
        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        let point = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -46.5)))
        XCTAssertEqual(placement(of: task).start, before.start - 30)
        XCTAssertEqual(placement(of: task).duration, 60)
        shot("09-start-time-drag")
        app.buttons["undoButton"].tap()
        XCTAssertEqual(placement(of: task).start, before.start)
        XCTAssertEqual(placement(of: task).duration, 60)
        let handleAgain = app.otherElements["move-移動の確認"]
        XCTAssertTrue(handleAgain.waitForExistence(timeout: 3))
        let again = handleAgain.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        again.press(forDuration: 0.05, thenDragTo: again.withOffset(CGVector(dx: 0, dy: -46.5)))
        XCTAssertEqual(placement(of: task).start, before.start - 30)
        app.terminate(); launch([])
        let restored = app.otherElements["task-移動の確認"]
        XCTAssertTrue(restored.waitForExistence(timeout: 3))
        XCTAssertEqual(placement(of: restored).start, before.start - 30)
        XCTAssertEqual(placement(of: restored).duration, 60)
    }
    func test10SwipeDaysAndKeepEachDaysPlan() {
        launch(["--reset-test-data"])
        let task = createAndPlaceSticky()
        let originalPlacement = task.value as? String
        let date = app.staticTexts["selectedDate"]
        let today = date.label
        app.buttons["次の日"].tap()
        let nextDay = date.label
        app.buttons["todayButton"].tap()
        app.buttons["前の日"].tap()
        let previousDay = date.label
        app.buttons["todayButton"].tap()

        let navigation = app.otherElements["dayNavigation"]
        navigation.swipeLeft()
        XCTAssertEqual(date.label, nextDay)
        XCTAssertFalse(task.exists)
        XCTAssertFalse(app.staticTexts["企画を考える日"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "fixed-チームミーティング").firstMatch.exists)
        shot("10-swipe-next-day")
        navigation.swipeRight()
        XCTAssertEqual(date.label, today)
        XCTAssertEqual(task.value as? String, originalPlacement)
        navigation.swipeRight()
        XCTAssertEqual(date.label, previousDay)
        XCTAssertFalse(task.exists)
        navigation.swipeLeft()
        XCTAssertEqual(date.label, today)

        let timeline = app.scrollViews["timeline"]
        let left = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.1))
        let right = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.1))
        right.press(forDuration: 0.01, thenDragTo: left)
        XCTAssertEqual(date.label, nextDay)
        left.press(forDuration: 0.01, thenDragTo: right)
        XCTAssertEqual(date.label, today)
        XCTAssertEqual(task.value as? String, originalPlacement)
    }
    func test12NamedColorsPersistAndApplyToStickyAndPreset() {
        launch(["--reset-test-data"])
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("色の確認")
        app.buttons["color-1"].tap()
        app.buttons["saveSticky"].tap()
        app.buttons["colorSettings"].tap()
        let name = app.textFields["color-name-1"]
        XCTAssertEqual(name.value as? String, "仕事")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "集中")
        app.buttons["saveColorNames"].tap()
        app.buttons["colorSettings"].tap()
        XCTAssertEqual(app.textFields["color-name-1"].value as? String, "集中")
        shot("11-color-settings")
        app.buttons["キャンセル"].tap()
        app.descendants(matching: .any).matching(identifier: "inbox-色の確認").firstMatch.tap()
        XCTAssertEqual(app.textFields["stickyTitle"].value as? String, "色の確認")
        XCTAssertEqual(app.buttons["color-1"].label, "集中")
        XCTAssertEqual(app.buttons["color-1"].value as? String, "選択中")
        shot("12-named-color-picker")
        app.buttons["キャンセル"].tap()
        app.terminate(); launch([])
        app.buttons["presetsButton"].tap()
        app.buttons["newPreset"].tap()
        app.textFields["presetTitle"].tap()
        app.textFields["presetTitle"].typeText("色のプリセット")
        XCTAssertEqual(app.buttons["color-1"].label, "集中")
        app.buttons["color-1"].tap()
        app.buttons["savePreset"].tap()
        app.buttons["preset-色のプリセット"].tap()
        app.buttons["closePresets"].tap()
        app.descendants(matching: .any).matching(identifier: "inbox-色のプリセット").firstMatch.tap()
        XCTAssertEqual(app.buttons["color-1"].label, "集中")
        XCTAssertEqual(app.buttons["color-1"].value as? String, "選択中")
    }
    func test11VerticalScrollAndInboxSwipeKeepDate() {
        launch()
        let date = app.staticTexts["selectedDate"].label
        app.otherElements["inboxTray"].scrollViews.firstMatch.swipeLeft()
        XCTAssertEqual(app.staticTexts["selectedDate"].label, date)
        let timeline = app.scrollViews["timeline"]
        let bottom = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.85))
        let top = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2))
        bottom.press(forDuration: 0.01, thenDragTo: top)
        XCTAssertEqual(app.staticTexts["selectedDate"].label, date)
        XCTAssertFalse(app.staticTexts["08:00"].isHittable)
    }
}
