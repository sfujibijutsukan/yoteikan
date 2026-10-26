import XCTest

final class YoteikanUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    func launch(_ args: [String] = ["--demo"]) { app = XCUIApplication(); app.launchArguments = args; app.launch(); XCTAssertTrue(app.buttons["presetsButton"].waitForExistence(timeout: 10)) }
    func shot(_ name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
    func test01DemoAndPresets() {
        launch()
        XCTAssertFalse(app.staticTexts["予定館"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "freeTimeBar").firstMatch.value as? String, "15時間30分")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "unplacedTimeBar").firstMatch.exists)
        XCTAssertLessThan(app.scrollViews["timeline"].frame.minY, app.frame.height * 0.25)
        XCTAssertGreaterThan(app.scrollViews["timeline"].frame.height, app.frame.height * 0.65)
        shot("01-day-planner")
        app.buttons["showStickyPool"].tap(); app.buttons["presetsButton"].tap()
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
        editInbox("集中作業"); app.buttons["duration-60"].tap(); app.buttons["saveSticky"].tap()
        app.buttons["undoButton"].tap()
        editInbox("集中作業")
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
        app.buttons["showStickyPool"].tap(); app.buttons["presetsButton"].tap(); app.buttons["newPreset"].tap()
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
        editInbox("色の確認")
        XCTAssertEqual(app.textFields["stickyTitle"].value as? String, "色の確認")
        XCTAssertEqual(app.buttons["color-1"].label, "集中")
        XCTAssertEqual(app.buttons["color-1"].value as? String, "選択中")
        shot("12-named-color-picker")
        app.buttons["キャンセル"].tap()
        app.terminate(); launch([])
        app.buttons["showStickyPool"].tap(); app.buttons["presetsButton"].tap()
        app.buttons["newPreset"].tap()
        app.textFields["presetTitle"].tap()
        app.textFields["presetTitle"].typeText("色のプリセット")
        XCTAssertEqual(app.buttons["color-1"].label, "集中")
        app.buttons["color-1"].tap()
        app.buttons["savePreset"].tap()
        app.buttons["preset-色のプリセット"].tap()
        app.buttons["closePresets"].tap()
        editInbox("色のプリセット")
        XCTAssertEqual(app.buttons["color-1"].label, "集中")
        XCTAssertEqual(app.buttons["color-1"].value as? String, "選択中")
    }
    func test13AddEditAndDeleteColorWithReplacement() {
        launch(["--reset-test-data"])
        app.buttons["colorSettings"].tap()
        app.buttons["addColor"].tap()
        let name = app.textFields["color-name-4"]
        if !name.isHittable { app.swipeUp() }
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "趣味")
        let hex = app.textFields["color-hex-4"]
        hex.tap()
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "C3D5F2")
        app.buttons["saveColorNames"].tap()
        app.buttons["colorSettings"].tap()
        XCTAssertEqual(app.textFields["color-name-4"].value as? String, "趣味")
        XCTAssertEqual(app.textFields["color-hex-4"].value as? String, "C3D5F2")
        shot("13-custom-colors")
        app.buttons["キャンセル"].tap()
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("趣味の時間")
        app.buttons["color-4"].tap()
        app.buttons["saveSticky"].tap()
        editInbox("趣味の時間")
        XCTAssertEqual(app.buttons["color-4"].value as? String, "選択中")
        shot("14-expanded-color-picker")
        app.buttons["キャンセル"].tap()
        app.buttons["showStickyPool"].tap(); app.buttons["presetsButton"].tap()
        app.buttons["newPreset"].tap()
        app.textFields["presetTitle"].tap()
        app.textFields["presetTitle"].typeText("趣味プリセット")
        app.buttons["color-4"].tap()
        app.buttons["savePreset"].tap()
        app.buttons["closePresets"].tap()
        app.buttons["colorSettings"].tap()
        let remove = app.buttons["delete-color-4"]
        if !remove.isHittable { app.swipeUp() }
        remove.tap()
        app.buttons["仕事に付け替える"].tap()
        app.buttons["saveColorNames"].tap()
        app.terminate(); launch([])
        editInbox("趣味の時間")
        XCTAssertFalse(app.buttons["color-4"].exists)
        XCTAssertEqual(app.buttons["color-1"].value as? String, "選択中")
        app.buttons["キャンセル"].tap()
        app.buttons["showStickyPool"].tap(); app.buttons["presetsButton"].tap()
        app.buttons["趣味プリセットのプリセットを編集"].tap()
        XCTAssertFalse(app.buttons["color-4"].exists)
        XCTAssertEqual(app.buttons["color-1"].value as? String, "選択中")
    }
    func test14PlanAtFiveAMAndKeepMidnightBoundary() {
        launch(["--reset-test-data"])
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("早朝の読書")
        app.buttons["saveSticky"].tap()
        let timeline = app.scrollViews["timeline"]
        let upper = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2))
        let lower = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.9))
        upper.press(forDuration: 0.01, thenDragTo: lower)
        let firstHour = app.staticTexts["05:00"]
        XCTAssertTrue(firstHour.waitForExistence(timeout: 3))
        XCTAssertTrue(firstHour.isHittable)
        let target = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0))
            .withOffset(CGVector(dx: 0, dy: firstHour.frame.minY - timeline.frame.minY + 1))
        let inbox = app.descendants(matching: .any).matching(identifier: "inbox-早朝の読書").firstMatch
        inbox.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: target)
        let task = app.otherElements["task-早朝の読書"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertEqual(task.value as? String, "05:00|30")
        app.buttons["zoomToggle"].tap()
        XCTAssertTrue(app.staticTexts["05:00"].isHittable)
        XCTAssertTrue(app.staticTexts["24:00"].isHittable)
        shot("15-five-am-plan")
        app.terminate(); launch([])
        app.buttons["zoomToggle"].tap()
        XCTAssertEqual(app.otherElements["task-早朝の読書"].value as? String, "05:00|30")
        app.otherElements["task-早朝の読書"].tap()
        app.buttons["editButton"].tap()
        XCTAssertTrue(app.staticTexts["5:00〜24:00"].exists)
    }
    func test15CustomizeHoursPersistAndRecoverOutsideSticky() {
        launch(["--reset-test-data"])
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("夜の計画")
        app.buttons["saveSticky"].tap()
        app.buttons["hoursSettings"].tap()
        chooseHour("20:00", picker: "planningStart")
        chooseHour("22:00", picker: "planningEnd")
        shot("16-planning-hours-settings")
        app.buttons["saveHours"].tap()
        app.buttons["zoomToggle"].tap()
        XCTAssertTrue(app.staticTexts["20:00"].isHittable)
        XCTAssertTrue(app.staticTexts["22:00"].isHittable)
        XCTAssertFalse(app.staticTexts["05:00"].exists)
        XCTAssertTrue(app.staticTexts["2時間"].exists)
        app.terminate(); launch([])
        app.buttons["hoursSettings"].tap()
        XCTAssertTrue(app.buttons["planningStart"].label.contains("20:00"))
        XCTAssertTrue(app.buttons["planningEnd"].label.contains("22:00"))
        chooseHour("19:00", picker: "planningStart")
        app.buttons["cancelHours"].tap()
        app.buttons["hoursSettings"].tap()
        XCTAssertTrue(app.buttons["planningStart"].label.contains("20:00"))
        app.buttons["cancelHours"].tap()
        let timeline = app.scrollViews["timeline"]
        let marker = app.staticTexts["20:00"]
        let target = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0))
            .withOffset(CGVector(dx: 0, dy: marker.frame.minY - timeline.frame.minY + 1))
        app.descendants(matching: .any).matching(identifier: "inbox-夜の計画").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: target)
        XCTAssertEqual(app.otherElements["task-夜の計画"].value as? String, "20:00|30")
        app.buttons["hoursSettings"].tap()
        chooseHour("21:00", picker: "planningStart")
        app.buttons["saveHours"].tap()
        XCTAssertFalse(app.otherElements["task-夜の計画"].exists)
        let outside = app.descendants(matching: .any).matching(identifier: "inbox-夜の計画").firstMatch
        XCTAssertTrue(outside.exists)
        XCTAssertTrue(outside.label.contains("時間外 20:00"))
        shot("17-custom-hours-and-outside-sticky")
        app.buttons["undoButton"].tap()
        XCTAssertEqual(app.otherElements["task-夜の計画"].value as? String, "20:00|30")
    }
    private func chooseHour(_ hour: String, picker: String) {
        app.buttons[picker].tap()
        let option = app.buttons[hour]
        for _ in 0..<4 {
            if option.exists && option.isHittable { break }
            app.swipeUp()
        }
        option.tap()
    }
    private func editInbox(_ title: String) {
        app.buttons["showStickyPool"].tap()
        let note = app.descendants(matching: .any).matching(identifier: "inbox-\(title)").firstMatch
        for _ in 0..<5 {
            if note.exists && note.isHittable { break }
            app.otherElements["inboxTray"].scrollViews.firstMatch.swipeUp()
        }
        note.tap()
        if !app.textFields["stickyTitle"].exists { app.buttons["editButton"].tap() }
    }
    func test16TwoZonesDragAndMemoPersist() {
        launch()
        let timeline = app.scrollViews["timeline"]
        let tray = app.otherElements["inboxTray"]
        XCTAssertLessThanOrEqual(timeline.frame.maxX, tray.frame.minX)
        XCTAssertFalse(app.otherElements["memoZone"].exists)
        shot("18-two-zone-planner")
        app.terminate(); launch(["--reset-test-data"])
        let task = createAndPlaceSticky()
        let before = task.value as? String
        app.buttons["notesButton"].tap()
        app.textViews["detailMemo"].tap()
        app.textViews["detailMemo"].typeText("読みたい章を確認する")
        app.buttons["saveDetailMemo"].tap()
        shot("19-detail-memo")
        app.buttons["closeNotes"].tap()
        XCTAssertEqual(task.value as? String, before)
        app.terminate(); launch([])
        let restored = app.otherElements["task-移動の確認"]
        XCTAssertEqual(restored.value as? String, before)
        restored.tap()
        app.buttons["notesButton"].tap()
        XCTAssertEqual(app.textViews["detailMemo"].value as? String, "読みたい章を確認する")
    }
    func test17LandscapeShowsThreeZonesAndKeepsSelection() {
        launch()
        app.otherElements["task-朝の読書"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let memo = app.otherElements["memoZone"]
        XCTAssertTrue(memo.waitForExistence(timeout: 5))
        let schedule = app.otherElements["scheduleZone"]
        let tray = app.otherElements["inboxTray"]
        XCTAssertLessThanOrEqual(schedule.frame.maxX, memo.frame.minX + 1)
        XCTAssertLessThanOrEqual(memo.frame.maxX, tray.frame.minX + 1)
        XCTAssertTrue(app.textViews["detailMemo"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "20-three-zone-planner"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertFalse(memo.exists)
        app.buttons["notesButton"].tap()
        XCTAssertTrue(app.staticTexts["朝の読書"].exists)
    }
    func test18SwitchSideZoneInOneTapAndKeepMemoDraft() {
        launch()
        let task = app.otherElements["task-資料作成"]
        task.tap()
        let before = task.value as? String
        app.buttons["showScheduleDetails"].tap()
        XCTAssertTrue(app.otherElements["sideDetail"].exists)
        XCTAssertFalse(app.otherElements["inboxTray"].exists)
        XCTAssertFalse(app.buttons["closeNotes"].exists)
        XCTAssertTrue(app.staticTexts["09:00〜10:00"].exists)
        app.textViews["detailMemo"].tap()
        app.textViews["detailMemo"].typeText("確認する資料")
        app.buttons["showStickyPool"].tap()
        XCTAssertTrue(app.otherElements["inboxTray"].exists)
        app.buttons["showScheduleDetails"].tap()
        XCTAssertEqual(app.textViews["detailMemo"].value as? String, "確認する資料")
        app.buttons["saveDetailMemo"].tap()
        XCTAssertEqual(task.value as? String, before)
        shot("21-switch-to-schedule-details")
        app.buttons["showStickyPool"].tap()
        XCTAssertTrue(app.otherElements["inboxTray"].exists)
    }
    func test19TapStickyForDetailsAndDropBackWhileDetailsAreOpen() {
        launch()
        app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch.tap()
        XCTAssertTrue(app.otherElements["sideDetail"].exists)
        XCTAssertTrue(app.buttons["editSideDetail"].exists)
        app.buttons["editSideDetail"].tap()
        app.buttons["duration-30"].tap()
        app.buttons["saveSticky"].tap()
        XCTAssertTrue(app.staticTexts["30分"].exists)
        app.buttons["showStickyPool"].tap()
        let timeline = app.scrollViews["timeline"]
        app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.3)))
        let task = app.otherElements["task-運動"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertEqual(placement(of: task).duration, 30)
        app.buttons["showScheduleDetails"].tap()
        let side = app.otherElements["sideZone"]
        app.otherElements["move-運動"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: side.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(app.otherElements["inboxTray"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch.exists)
        XCTAssertFalse(task.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch.label.contains("30分"))
    }
    func test11VerticalScrollAndInboxSwipeKeepDate() {
        launch()
        let date = app.staticTexts["selectedDate"].label
        app.otherElements["inboxTray"].scrollViews.firstMatch.swipeUp()
        XCTAssertEqual(app.staticTexts["selectedDate"].label, date)
        let timeline = app.scrollViews["timeline"]
        let bottom = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.85))
        let top = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2))
        bottom.press(forDuration: 0.01, thenDragTo: top)
        XCTAssertEqual(app.staticTexts["selectedDate"].label, date)
        XCTAssertFalse(app.staticTexts["08:00"].isHittable)
    }
    func test20ZoomShortEventsWithoutVisualOverlap() {
        launch(["--demo", "--short-events-test"])
        let first = app.otherElements["task-読書5分"]
        let second = app.otherElements["task-休憩5分"]
        let third = app.otherElements["task-確認5分"]
        let meeting = app.otherElements["fixed-会議5分"]
        let call = app.otherElements["fixed-連絡5分"]
        func checkFrames() {
            for (a, b) in [(first, second), (second, third), (third, meeting), (meeting, call)] {
                XCTAssertLessThan(a.frame.maxY, b.frame.minY, "\(a.identifier) overlaps \(b.identifier)")
            }
            XCTAssertEqual(first.value as? String, "08:00|5")
            XCTAssertEqual(second.value as? String, "08:05|5")
            XCTAssertEqual(third.value as? String, "08:10|5")
        }
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        checkFrames()
        XCTAssertFalse(app.otherElements["resize-読書5分"].exists)
        let baseHeight = first.frame.height
        for label in ["2倍", "4倍", "8倍"] {
            app.buttons["zoomIn"].tap()
            XCTAssertEqual(app.staticTexts["zoomLevel"].label, label)
            checkFrames()
        }
        XCTAssertGreaterThan(first.frame.height, baseHeight * 7)
        XCTAssertGreaterThan(first.frame.height, 54)
        XCTAssertFalse(app.buttons["zoomIn"].isEnabled)
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(call.isHittable)
        shot("22-five-minute-zoom")
        first.tap()
        XCTAssertTrue(app.otherElements["move-読書5分"].exists)
        let handle = app.otherElements["resize-読書5分"]
        XCTAssertTrue(handle.exists)
        let point = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Two adjacent five-minute slots provide the actual screen distance.
        let fiveMinutes = second.frame.minY - first.frame.minY
        point.press(forDuration: 0.15, thenDragTo: point.withOffset(CGVector(dx: 0, dy: fiveMinutes)))
        XCTAssertEqual(first.value as? String, "08:00|10")
        app.buttons["undoButton"].tap()
        XCTAssertEqual(first.value as? String, "08:00|5")
        let move = app.otherElements["move-読書5分"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        move.press(forDuration: 0.05, thenDragTo: move.withOffset(CGVector(dx: 0, dy: fiveMinutes)))
        XCTAssertEqual(first.value as? String, "08:05|5")
        XCTAssertEqual(second.value as? String, "08:05|5")
        app.buttons["undoButton"].tap()
        XCTAssertEqual(first.value as? String, "08:00|5")
        app.buttons["zoomToggle"].tap()
        XCTAssertEqual(app.staticTexts["zoomLevel"].label, "全日")
        checkFrames()
        app.buttons["zoomToggle"].tap()
        XCTAssertEqual(app.staticTexts["zoomLevel"].label, "8倍")
        checkFrames()
        for label in ["4倍", "2倍", "1倍"] {
            app.buttons["zoomOut"].tap()
            XCTAssertEqual(app.staticTexts["zoomLevel"].label, label)
            checkFrames()
        }
        XCTAssertFalse(app.buttons["zoomOut"].isEnabled)
        shot("23-five-minute-standard")
    }
    func test21ZoomKeepsVisibleHourAndZoneLayout() {
        launch()
        let timeline = app.scrollViews["timeline"]
        let axis = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8))
        axis.press(forDuration: 0.01, thenDragTo: axis.withOffset(CGVector(dx: 0, dy: -210)))
        let visible = (8...23).map { app.staticTexts[String(format: "%02d:00", $0)] }
            .first { $0.isHittable && $0.frame.minY >= timeline.frame.minY && $0.frame.minY < timeline.frame.maxY }
        XCTAssertNotNil(visible)
        let hour = visible!.label
        app.buttons["zoomIn"].tap()
        XCTAssertTrue(app.staticTexts[hour].isHittable)
        XCTAssertEqual(app.staticTexts["zoomLevel"].label, "2倍")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.otherElements["memoZone"].exists)
        XCTAssertEqual(app.staticTexts["zoomLevel"].label, "2倍")
        let schedule = app.otherElements["scheduleZone"]
        let memo = app.otherElements["memoZone"]
        XCTAssertLessThanOrEqual(schedule.frame.maxX, memo.frame.minX + 1)
        XCUIDevice.shared.orientation = .portrait
    }
    func test22PinchTimelinePreservesTimeAndTasks() {
        launch()
        let timeline = app.scrollViews["timeline"]
        let surface = app.descendants(matching: .any).matching(identifier: "timelineZoomSurface").firstMatch
        func zoom() -> Double { Double(app.staticTexts["zoomLevel"].label.replacingOccurrences(of: "倍", with: "")) ?? 0 }
        let reading = app.otherElements["task-朝の読書"].value as? String
        let work = app.otherElements["task-資料作成"].value as? String
        let eleven = app.staticTexts["11:00"]
        let beforeY = eleven.frame.midY
        let center = timeline.frame.midY
        surface.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(zoom(), 1.4)
        XCTAssertLessThan(zoom(), 8)
        XCTAssertTrue(eleven.isHittable)
        XCTAssertEqual(eleven.frame.midY, center + (beforeY - center) * zoom(), accuracy: 65)
        XCTAssertEqual(app.otherElements["task-朝の読書"].value as? String, reading)
        XCTAssertEqual(app.otherElements["task-資料作成"].value as? String, work)
        shot("24-pinch-timeline")
        let expanded = zoom()
        surface.pinch(withScale: 0.5, velocity: -1)
        XCTAssertLessThan(zoom(), expanded)
        while app.buttons["zoomOut"].isEnabled { app.buttons["zoomOut"].tap() }
        XCTAssertEqual(zoom(), 1)
        surface.pinch(withScale: 0.5, velocity: -1)
        XCTAssertEqual(zoom(), 1)
        for _ in 0..<3 { app.buttons["zoomIn"].tap() }
        XCTAssertEqual(zoom(), 8)
        surface.pinch(withScale: 2, velocity: 1)
        XCTAssertEqual(zoom(), 8)
        surface.pinch(withScale: 0.5, velocity: -1)
        XCTAssertLessThan(zoom(), 7)
        let retained = app.staticTexts["zoomLevel"].label
        app.buttons["zoomToggle"].tap()
        XCTAssertEqual(app.staticTexts["zoomLevel"].label, "全日")
        app.buttons["zoomToggle"].tap()
        XCTAssertEqual(app.staticTexts["zoomLevel"].label, retained)
        app.buttons["zoomToggle"].tap()
        surface.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThanOrEqual(zoom(), 1)
        XCTAssertEqual(app.otherElements["task-朝の読書"].value as? String, reading)
        XCTAssertEqual(app.otherElements["task-資料作成"].value as? String, work)
    }
}
