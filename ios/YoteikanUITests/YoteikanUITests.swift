import XCTest

final class YoteikanUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    func launch(_ args: [String] = ["--demo"]) { app = XCUIApplication(); app.launchArguments = args; app.launch(); XCTAssertTrue(app.buttons["presetsButton"].waitForExistence(timeout: 10)) }
    func shot(_ name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
    func test31LongPressPreviewAutomaticallyDisappearsOnBothPages() {
        launch()
        let task = app.otherElements["task-朝の読書"]
        let timing = task.value as? String
        task.press(forDuration: 8)
        XCTAssertFalse(app.otherElements["memoPreview"].exists)
        XCTAssertFalse(app.textViews["scheduleMemo"].exists)
        XCTAssertFalse(app.buttons["closeScheduleMemo"].exists)
        XCTAssertEqual(task.value as? String, timing)
        selectTab("1日表示")
        let block = app.descendants(matching: .any).matching(identifier: "fullDayBlock-朝の読書").firstMatch
        block.press(forDuration: 8)
        XCTAssertFalse(app.otherElements["memoPreview"].exists)
        XCTAssertFalse(app.buttons["closeScheduleMemo"].exists)
        XCTAssertTrue(app.tabBars.buttons["1日表示"].isSelected)
        selectTab("計画")
        selectDetails()
        XCTAssertEqual(app.textViews["detailMemo"].value as? String, "気になる章をゆっくり読む")
        XCTAssertEqual(task.value as? String, timing)
    }
    func test32CalendarPreviewDoesNotPresentEditor() {
        launch()
        app.otherElements["fixed-チームミーティング"].press(forDuration: 1)
        XCTAssertFalse(app.otherElements["memoPreview"].exists)
        XCTAssertFalse(app.buttons["closeScheduleMemo"].exists)
        selectTab("1日表示")
        app.descendants(matching: .any).matching(identifier: "fullDayBlock-チームミーティング").firstMatch.press(forDuration: 1)
        XCTAssertFalse(app.otherElements["memoPreview"].exists)
        XCTAssertFalse(app.textViews["scheduleMemo"].exists)
        XCTAssertTrue(app.tabBars.buttons["1日表示"].isSelected)
    }
    private func selectTab(_ name: String) { app.tabBars.buttons[name].tap() }
    private func selectDetails() { app.buttons["showScheduleDetails"].tap() }
    private func editSelected() {
        if app.textFields["stickyTitle"].exists { return }
        selectDetails()
        app.buttons["editSideDetail"].tap()
    }
    private func undoChange() {
        selectTab("設定")
        app.buttons["undoButton"].tap()
        selectTab("計画")
    }
    private func unplaceSelected() { selectDetails(); app.buttons["unplaceButton"].tap() }
    private func pinch(_ factor: CGFloat) {
        let surface = app.descendants(matching: .any).matching(identifier: "timelineZoomSurface").firstMatch
        surface.pinch(withScale: factor, velocity: factor > 1 ? 1 : -1)
    }
    private func zoomLabel() -> String {
        app.descendants(matching: .any).matching(identifier: "timelineZoomSurface").firstMatch.value as? String ?? ""
    }
    private func toggleDay() { selectTab(app.tabBars.buttons["1日表示"].isSelected ? "計画" : "1日表示") }
    private func openSetting(_ identifier: String) {
        selectTab("設定")
        let action = app.buttons[identifier]
        for _ in 0..<3 {
            if action.isHittable { break }
            app.swipeUp()
        }
        action.tap()
    }
    func test30UnifiedSettingsAndStickyEditing() {
        launch(["--reset-test-data", "--demo"])
        XCTAssertFalse(app.buttons["hoursSettings"].exists)
        XCTAssertFalse(app.buttons["colorSettings"].exists)
        XCTAssertFalse(app.buttons["calendarSettings"].exists)
        selectTab("設定")
        XCTAssertTrue(app.buttons["hoursSettings"].exists)
        XCTAssertTrue(app.buttons["calendarSettings"].exists)
        XCTAssertTrue(app.buttons["colorSettings"].exists)
        shot("37-unified-settings")
        app.buttons["settingsEditStickies"].tap()
        app.buttons["settingsSticky-朝の読書"].tap()
        XCTAssertTrue(app.textFields["stickyTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["stickyTitle"].value as? String, "朝の読書")
        app.buttons["duration-45"].tap()
        app.buttons["saveSticky"].tap()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 3))
        openSetting("settingsEditStickies")
        XCTAssertTrue(app.buttons["settingsSticky-朝の読書"].waitForExistence(timeout: 3))
        shot("38-settings-sticky-list")
        app.buttons["closeSettingsStickies"].tap()
        XCTAssertEqual(app.otherElements["task-朝の読書"].value as? String, "08:00|45")
        openSetting("settingsPresets")
        XCTAssertTrue(app.buttons["newPreset"].waitForExistence(timeout: 3))
        app.buttons["closePresets"].tap()
        openSetting("hoursSettings")
        XCTAssertTrue(app.buttons["saveHours"].waitForExistence(timeout: 3))
        app.buttons["cancelHours"].tap()
        openSetting("colorSettings")
        XCTAssertTrue(app.buttons["saveColorNames"].waitForExistence(timeout: 3))
        app.buttons["キャンセル"].tap()
        openSetting("calendarSettings")
        XCTAssertTrue(app.buttons["closeCalendar"].waitForExistence(timeout: 3))
        app.buttons["closeCalendar"].tap()
    }
    func test29SidebarPositionPersistsAndSupportsDragAndDetails() {
        launch(["--reset-test-data", "--demo"])
        let schedule = app.otherElements["scheduleZone"]
        let side = app.otherElements["sideZone"]
        XCTAssertLessThan(schedule.frame.maxX, side.frame.maxX)
        selectTab("設定")
        app.segmentedControls["sidebarPosition"].buttons["左"].tap()
        shot("34-sidebar-position-settings")
        selectTab("計画")
        XCTAssertLessThanOrEqual(side.frame.maxX, schedule.frame.minX)
        shot("35-sidebar-left")
        let note = app.otherElements["inbox-読書"]
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: app.scrollViews["timeline"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        let task = app.otherElements["task-読書"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        let before = task.value as? String
        app.buttons["showScheduleDetails"].tap()
        XCTAssertLessThanOrEqual(side.frame.maxX, schedule.frame.minX)
        XCTAssertTrue(app.textViews["detailMemo"].exists)
        app.textViews["detailMemo"].tap(); app.textViews["detailMemo"].typeText("下書きを保持")
        selectTab("設定")
        app.segmentedControls["sidebarPosition"].buttons["右"].tap()
        selectTab("計画")
        XCTAssertLessThanOrEqual(schedule.frame.maxX, side.frame.minX)
        XCTAssertEqual(app.textViews["detailMemo"].value as? String, "下書きを保持")
        selectTab("設定")
        app.segmentedControls["sidebarPosition"].buttons["左"].tap()
        selectTab("計画")
        XCTAssertEqual(app.textViews["detailMemo"].value as? String, "下書きを保持")
        app.buttons["showStickyPool"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        let memo = app.otherElements["memoZone"]
        XCTAssertTrue(memo.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(side.frame.maxX, memo.frame.minX)
        XCTAssertLessThanOrEqual(memo.frame.maxX, schedule.frame.minX)
        XCTAssertEqual(task.value as? String, before)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "36-sidebar-left-landscape"; attachment.lifetime = .keepAlways; add(attachment)
        XCUIDevice.shared.orientation = .portrait
        let handle = app.descendants(matching: .any).matching(identifier: "move-読書").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: app.otherElements["inboxTray"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(app.otherElements["inbox-読書"].exists)
        app.terminate(); launch(["--demo"])
        XCTAssertLessThanOrEqual(side.frame.maxX, schedule.frame.minX)
        selectTab("設定")
        XCTAssertTrue(app.segmentedControls["sidebarPosition"].buttons["左"].isSelected)
        app.segmentedControls["sidebarPosition"].buttons["右"].tap()
        selectTab("計画")
        XCTAssertLessThanOrEqual(schedule.frame.maxX, side.frame.minX)
    }
    private func revealReminderSettings() {
        for _ in 0..<4 {
            if app.buttons["enableReminders"].isHittable || app.staticTexts["scheduledReminders"].isHittable { return }
            app.swipeUp()
        }
    }
    func test28ReminderSettingsPersistAndSchedule() {
        launch(["--reset-test-data"])
        app.buttons["次の日"].tap()
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap(); app.textFields["stickyTitle"].typeText("通知確認")
        app.buttons["duration-30"].tap()
        for _ in 0..<4 {
            if app.steppers["reminderMinutes"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.steppers["reminderMinutes"].label.contains("5分前"))
        app.steppers["reminderMinutes"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.steppers["reminderMinutes"].label.contains("6分前"))
        shot("32-sticky-reminder")
        app.buttons["saveSticky"].tap()
        let note = app.descendants(matching: .any).matching(identifier: "inbox-通知確認").firstMatch
        revealInbox(note)
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: app.scrollViews["timeline"].coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.2)))
        XCTAssertTrue(app.otherElements["task-通知確認"].waitForExistence(timeout: 3))
        selectTab("設定")
        revealReminderSettings()
        if app.buttons["enableReminders"].exists {
            app.buttons["enableReminders"].tap()
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if alert.waitForExistence(timeout: 3) {
                let allow = alert.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == '許可'" )).firstMatch
                XCTAssertTrue(allow.exists); allow.tap()
            }
        }
        let count = app.staticTexts["scheduledReminders"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(NSPredicate(format: "label CONTAINS '1件'").evaluate(with: count))
        shot("33-reminder-settings")
        selectTab("計画")
        app.terminate(); launch([])
        app.buttons["次の日"].tap()
        let task = app.otherElements["task-通知確認"]
        XCTAssertTrue(task.waitForExistence(timeout: 3)); task.tap()
        editSelected()
        for _ in 0..<4 {
            if app.steppers["reminderMinutes"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.steppers["reminderMinutes"].label.contains("6分前"))
        app.switches["reminderToggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertFalse(app.steppers["reminderMinutes"].exists)
        app.buttons["saveSticky"].tap()
        selectTab("設定")
        revealReminderSettings()
        XCTAssertTrue(NSPredicate(format: "label CONTAINS '0件'").evaluate(with: app.staticTexts["scheduledReminders"]))
    }
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
        undoChange()
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
        undoChange()
        let handle = app.otherElements["resize-資料作成"]
        XCTAssertTrue(handle.exists)
        let point = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(forDuration: 0.15, thenDragTo: point.withOffset(CGVector(dx: 0, dy: 46.5)))
        XCTAssertEqual(task.value as? String, "09:00|90")
        shot("05-resize-overlap")
        unplaceSelected()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox-資料作成").firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["task-資料作成"].exists)
        undoChange()
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
        toggleDay(); Thread.sleep(forTimeInterval: 0.8); shot("06-day-overview")
    }
    func test05CalendarAccessAndRealEventKitRead() {
        launch(["--calendar-test"])
        openSetting("calendarSettings")
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
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "inbox-散歩").count, 1)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "inbox-散歩").count, 2)
    }
    func test07CalendarSelectionChangesVisibleEvents() {
        launch(["--calendar-test"])
        openSetting("calendarSettings")
        let toggle = app.switches["calendar-予定館・動作確認用"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["closeCalendar"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "fixed-チームミーティング").firstMatch.exists)
        openSetting("calendarSettings"); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); app.buttons["closeCalendar"].tap()
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
        revealInbox(inbox)
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
        undoChange()
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
        openSetting("colorSettings")
        let name = app.textFields["color-name-1"]
        XCTAssertEqual(name.value as? String, "仕事")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "集中")
        app.buttons["saveColorNames"].tap()
        openSetting("colorSettings")
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
        openSetting("colorSettings")
        app.buttons["addColor"].tap()
        let name = app.textFields["color-name-4"]
        if !name.isHittable { app.swipeUp() }
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "趣味")
        let hex = app.textFields["color-hex-4"]
        hex.tap()
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "C3D5F2")
        app.buttons["saveColorNames"].tap()
        openSetting("colorSettings")
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
        openSetting("colorSettings")
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
        revealInbox(inbox)
        inbox.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: target)
        let task = app.otherElements["task-早朝の読書"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertEqual(task.value as? String, "05:00|30")
        toggleDay()
        XCTAssertTrue(app.staticTexts["05:00"].isHittable)
        XCTAssertTrue(app.staticTexts["24:00"].isHittable)
        shot("15-five-am-plan")
        app.terminate(); launch([])
        XCTAssertEqual(app.otherElements["task-早朝の読書"].value as? String, "05:00|30")
        openSetting("settingsEditStickies")
        app.buttons["settingsSticky-早朝の読書"].tap()
        XCTAssertTrue(app.staticTexts["5:00〜24:00"].exists)
    }
    func test15CustomizeHoursPersistAndRecoverOutsideSticky() {
        launch(["--reset-test-data"])
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("夜の計画")
        app.buttons["saveSticky"].tap()
        openSetting("hoursSettings")
        chooseHour("20:00", picker: "planningStart")
        chooseHour("22:00", picker: "planningEnd")
        shot("16-planning-hours-settings")
        app.buttons["saveHours"].tap()
        toggleDay()
        XCTAssertTrue(app.staticTexts["20:00"].isHittable)
        XCTAssertTrue(app.staticTexts["22:00"].isHittable)
        XCTAssertFalse(app.staticTexts["05:00"].exists)
        XCTAssertTrue(app.staticTexts["空き 2時間"].exists)
        app.terminate(); launch([])
        openSetting("hoursSettings")
        XCTAssertTrue(app.buttons["planningStart"].label.contains("20:00"))
        XCTAssertTrue(app.buttons["planningEnd"].label.contains("22:00"))
        chooseHour("19:00", picker: "planningStart")
        app.buttons["cancelHours"].tap()
        openSetting("hoursSettings")
        XCTAssertTrue(app.buttons["planningStart"].label.contains("20:00"))
        app.buttons["cancelHours"].tap()
        let timeline = app.scrollViews["timeline"]
        let marker = app.staticTexts["20:00"]
        let target = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0))
            .withOffset(CGVector(dx: 0, dy: marker.frame.minY - timeline.frame.minY + 1))
        let evening = app.descendants(matching: .any).matching(identifier: "inbox-夜の計画").firstMatch
        revealInbox(evening)
        evening.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: target)
        XCTAssertEqual(app.otherElements["task-夜の計画"].value as? String, "20:00|30")
        openSetting("hoursSettings")
        chooseHour("21:00", picker: "planningStart")
        app.buttons["saveHours"].tap()
        XCTAssertFalse(app.otherElements["task-夜の計画"].exists)
        let outside = app.descendants(matching: .any).matching(identifier: "inbox-夜の計画").firstMatch
        XCTAssertTrue(outside.exists)
        XCTAssertTrue(outside.label.contains("時間外 20:00"))
        shot("17-custom-hours-and-outside-sticky")
        undoChange()
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
    private func revealInbox(_ note: XCUIElement) {
        for _ in 0..<8 {
            if note.exists && note.isHittable { break }
            app.otherElements["inboxTray"].scrollViews.firstMatch.swipeUp()
        }
    }
    private func editInbox(_ title: String) {
        app.buttons["showStickyPool"].tap()
        let note = app.descendants(matching: .any).matching(identifier: "inbox-\(title)").firstMatch
        revealInbox(note)
        note.tap()
        if !app.textFields["stickyTitle"].exists { editSelected() }
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
        selectDetails()
        app.textViews["detailMemo"].tap()
        app.textViews["detailMemo"].typeText("読みたい章を確認する")
        app.buttons["saveDetailMemo"].tap()
        shot("19-detail-memo")
        app.buttons["showStickyPool"].tap()
        XCTAssertEqual(task.value as? String, before)
        app.terminate(); launch([])
        let restored = app.otherElements["task-移動の確認"]
        XCTAssertEqual(restored.value as? String, before)
        restored.tap()
        selectDetails()
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
        selectDetails()
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
        let initialHeight = first.frame.height
        for _ in 0..<3 { pinch(2) }
        XCTAssertGreaterThan(first.frame.height, initialHeight * 6)
        XCTAssertLessThan(first.frame.maxY, second.frame.minY)
        first.tap()
        let resize = app.otherElements["resize-読書5分"]
        XCTAssertTrue(resize.exists)
        let fiveMinutes = second.frame.minY - first.frame.minY
        let point = resize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(forDuration: 0.2, thenDragTo: point.withOffset(CGVector(dx: 0, dy: fiveMinutes)))
        XCTAssertEqual(first.value as? String, "08:00|10")
        undoChange()
        XCTAssertEqual(first.value as? String, "08:00|5")
        shot("22-five-minute-zoom")
    }
    func test21ZoomKeepsVisibleHourAndZoneLayout() {
        launch()
        pinch(2)
        let zoom = zoomLabel()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["memoZone"].waitForExistence(timeout: 3))
        XCTAssertEqual(zoomLabel(), zoom)
        XCTAssertLessThanOrEqual(app.otherElements["scheduleZone"].frame.maxX, app.otherElements["memoZone"].frame.minX)
        XCUIDevice.shared.orientation = .portrait
    }
    func test23ScrollFromStickyAndCalendarEventPreservesPlans() {
        launch()
        let task = app.otherElements["task-資料作成"]
        let original = task.value as? String
        let date = app.staticTexts["selectedDate"].label
        let marker = app.staticTexts["10:00"]
        let before = marker.frame.minY
        let point = task.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
        point.press(forDuration: 0.01, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -140)))
        XCTAssertLessThan(marker.frame.minY, before - 50)
        XCTAssertEqual(task.value as? String, original)
        XCTAssertEqual(app.staticTexts["selectedDate"].label, date)
        let viewport = app.scrollViews["timeline"].frame.insetBy(dx: 8, dy: 12)
        let fixed = ["fixed-チームミーティング", "fixed-打ち合わせ"].map { app.otherElements[$0] }
            .first { $0.isHittable && $0.frame.intersection(viewport).height > 30 }
        guard let fixed else { return XCTFail("No calendar event is visible after scrolling") }
        let movedY = marker.frame.minY
        let hit = fixed.frame.intersection(viewport)
        let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: hit.midX, dy: hit.midY))
        from.press(forDuration: 0.01, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 110)))
        XCTAssertGreaterThan(marker.frame.minY, movedY + 40)
        XCTAssertEqual(task.value as? String, original)
        XCTAssertEqual(app.staticTexts["selectedDate"].label, date)
        shot("25-scroll-on-event")
    }
    private func adjustDailyCount(by delta: Int) {
        let stepper = app.steppers["presetDailyCount"]
        if !stepper.isHittable { app.swipeUp() }
        for _ in 0..<abs(delta) { stepper.buttons.element(boundBy: delta > 0 ? 1 : 0).tap() }
    }
    private func inboxCount(_ title: String) -> Int {
        app.descendants(matching: .any).matching(identifier: "inbox-\(title)").count
    }
    func test24DailyPresetCountsPersistWithoutRecreatingDeletedNotes() {
        launch(["--reset-test-data"])
        XCTAssertEqual(inboxCount("読書"), 1)
        app.buttons["presetsButton"].tap()
        for (name, extra) in [("歯磨き", 1), ("ごはん", 2)] {
            app.buttons["newPreset"].tap()
            app.textFields["presetTitle"].tap(); app.textFields["presetTitle"].typeText(name)
            adjustDailyCount(by: extra)
            app.buttons["savePreset"].tap()
        }
        app.buttons["edit-preset-歯磨き"].tap()
        XCTAssertTrue(app.steppers["presetDailyCount"].label.contains("2"))
        shot("26-daily-preset-count")
        app.buttons["キャンセル"].tap()
        app.buttons["closePresets"].tap()
        XCTAssertEqual(inboxCount("歯磨き"), 2)
        XCTAssertEqual(inboxCount("ごはん"), 3)
        app.buttons["次の日"].tap()
        XCTAssertEqual(inboxCount("歯磨き"), 2)
        XCTAssertEqual(inboxCount("ごはん"), 3)
        app.otherElements["inboxTray"].scrollViews.firstMatch.swipeUp()
        shot("27-daily-stickies")
        app.buttons["todayButton"].tap()
        XCTAssertEqual(inboxCount("歯磨き"), 2)
        app.terminate(); launch([])
        XCTAssertEqual(inboxCount("歯磨き"), 2)
        XCTAssertEqual(inboxCount("ごはん"), 3)
        editInbox("歯磨き")
        for _ in 0..<4 {
            if app.buttons["deleteSticky"].exists && app.buttons["deleteSticky"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["deleteSticky"].tap()
        app.buttons["showStickyPool"].tap()
        XCTAssertEqual(inboxCount("歯磨き"), 1)
        app.terminate(); launch([])
        XCTAssertEqual(inboxCount("歯磨き"), 1)
        app.buttons["次の日"].tap()
        XCTAssertEqual(inboxCount("歯磨き"), 2)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(inboxCount("歯磨き"), 1)
    }
    func test25DailyPresetCountEditCancelAndDisable() {
        launch(["--reset-test-data"])
        app.buttons["presetsButton"].tap()
        app.buttons["edit-preset-読書"].tap()
        adjustDailyCount(by: 2)
        app.buttons["savePreset"].tap()
        app.buttons["closePresets"].tap()
        XCTAssertEqual(inboxCount("読書"), 3)
        app.buttons["presetsButton"].tap()
        app.buttons["edit-preset-読書"].tap()
        adjustDailyCount(by: 1)
        app.buttons["キャンセル"].tap()
        app.buttons["edit-preset-読書"].tap()
        XCTAssertTrue(app.steppers["presetDailyCount"].label.contains("3"))
        adjustDailyCount(by: -3)
        app.buttons["savePreset"].tap()
        app.buttons["closePresets"].tap()
        XCTAssertEqual(inboxCount("読書"), 3)
        app.buttons["次の日"].tap()
        XCTAssertEqual(inboxCount("読書"), 0)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(inboxCount("読書"), 3)
        app.terminate(); launch([])
        app.buttons["presetsButton"].tap()
        app.buttons["edit-preset-読書"].tap()
        XCTAssertTrue(app.steppers["presetDailyCount"].label.contains("0"))
    }
    func test26FullScreenDayTimelineAndReturn() {
        launch()
        XCTAssertFalse(app.buttons["zoomIn"].exists)
        XCTAssertFalse(app.buttons["zoomOut"].exists)
        XCTAssertFalse(app.buttons["notesButton"].exists)
        XCTAssertFalse(app.buttons["fullDayButton"].exists)
        XCTAssertFalse(app.buttons["plannerSettings"].exists)
        XCTAssertFalse(app.staticTexts["zoomLevel"].exists)
        shot("39-glass-plan-tab")
        pinch(2)
        let zoom = zoomLabel()
        let task = app.otherElements["task-朝の読書"]
        task.tap()
        let before = task.value as? String
        selectTab("1日表示")
        let timeline = app.scrollViews["fullDayTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(timeline.frame.width, app.frame.width * 0.85)
        XCTAssertTrue(timeline.staticTexts["05:00"].isHittable)
        XCTAssertTrue(timeline.staticTexts["24:00"].isHittable)
        XCTAssertFalse(app.buttons["closeFullDay"].exists)
        shot("40-glass-day-tab")
        selectTab("設定")
        XCTAssertTrue(app.buttons["hoursSettings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["closePlannerSettings"].exists)
        shot("41-glass-settings-tab")
        selectTab("計画")
        XCTAssertEqual(zoomLabel(), zoom)
        XCTAssertEqual(task.value as? String, before)
        selectDetails()
        XCTAssertTrue(app.textViews["detailMemo"].exists)
    }
    func test27FullScreenShortNotesAndUnscheduledDay() {
        launch(["--demo", "--short-events-test"])
        selectTab("1日表示")
        let timeline = app.scrollViews["fullDayTimeline"]
        let reading = timeline.descendants(matching: .any).matching(identifier: "fullDayBlock-読書5分").firstMatch
        let rest = timeline.descendants(matching: .any).matching(identifier: "fullDayBlock-休憩5分").firstMatch
        XCTAssertTrue(reading.exists)
        XCTAssertTrue(rest.exists)
        XCTAssertGreaterThanOrEqual(reading.frame.height, 42)
        XCTAssertTrue(reading.label.contains("読書5分"))
        shot("31-folded-short-events")
        XCTAssertLessThanOrEqual(reading.frame.maxY, rest.frame.minY)
        XCTAssertFalse(app.segmentedControls["fullDayMode"].exists)
        selectTab("計画")
        XCTAssertEqual(app.otherElements["task-読書5分"].value as? String, "08:00|5")
        app.buttons["次の日"].tap()
        selectTab("1日表示")
        XCTAssertTrue(app.staticTexts["予定を配置するとここに表示されます"].exists)
        selectTab("計画")
    }
    func test37PinchKeepsTimeUnderFingerCenter() {
        launch()
        let reading = app.otherElements["task-朝の読書"]
        let surface = app.descendants(matching: .any).matching(identifier: "timelineZoomSurface").firstMatch
        func centerMinute() -> CGFloat {
            480 + (surface.frame.midY - reading.frame.minY) / (reading.frame.height + 4) * 30
        }
        let before = centerMinute()
        pinch(1.6)
        XCTAssertEqual(centerMinute(), before, accuracy: 5)
        pinch(0.8)
        XCTAssertEqual(centerMinute(), before, accuracy: 5)
        XCTAssertEqual(reading.value as? String, "08:00|30")
    }
    func test35FoldedPlanningKeepsTasksEditable() {
        launch()
        app.buttons["foldPlanner"].tap()
        let timeline = app.scrollViews["foldedPlannerTimeline"]
        XCTAssertTrue(timeline.exists)
        let reading = app.otherElements["task-朝の読書"]
        let work = app.otherElements["task-資料作成"]
        XCTAssertGreaterThanOrEqual(reading.frame.height, 42)
        XCTAssertTrue(app.otherElements["fixed-打ち合わせ"].isHittable)
        shot("49-folded-planning")
        work.tap()
        let move = app.otherElements["move-資料作成"]
        let origin = move.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 20)))
        XCTAssertEqual(work.value as? String, "09:20|60")
        XCTAssertEqual(reading.value as? String, "08:00|30")
        let resize = app.otherElements["resize-資料作成"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        resize.press(forDuration: 0.15, thenDragTo: resize.withOffset(CGVector(dx: 0, dy: 22)))
        XCTAssertEqual(work.value as? String, "09:20|80")
        XCTAssertEqual(reading.value as? String, "08:00|30")
        work.press(forDuration: 1)
        XCTAssertFalse(app.otherElements["memoPreview"].exists)
        XCTAssertFalse(app.buttons["closeScheduleMemo"].exists)
        app.buttons["foldPlanner"].tap()
        XCTAssertTrue(app.scrollViews["timeline"].exists)
        XCTAssertEqual(work.value as? String, "09:20|80")
    }
    func test36FoldedPlanningKeepsFiveMinuteNotesReadable() {
        launch(["--demo", "--short-events-test"])
        app.buttons["newStickyButton"].tap()
        app.textFields["stickyTitle"].tap()
        app.textFields["stickyTitle"].typeText("運動")
        app.buttons["saveSticky"].tap()
        app.buttons["foldPlanner"].tap()
        let reading = app.otherElements["task-読書5分"]
        let rest = app.otherElements["task-休憩5分"]
        XCTAssertGreaterThanOrEqual(reading.frame.height, 42)
        XCTAssertLessThanOrEqual(reading.frame.maxY, rest.frame.minY)
        shot("50-folded-planning-short-notes")
        let note = app.descendants(matching: .any).matching(identifier: "inbox-運動").firstMatch
        let destination = reading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -16))
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: destination)
        XCTAssertTrue(app.otherElements["task-運動"].waitForExistence(timeout: 3))
        XCTAssertEqual(reading.value as? String, "08:00|5")
    }
    func test33StickyPaperAppearance() {
        launch()
        XCTAssertTrue(app.otherElements["inbox-運動"].exists)
        XCTAssertEqual(app.otherElements["task-朝の読書"].value as? String, "08:00|30")
        shot("45-sticky-paper-plan")
        selectTab("1日表示")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fullDayBlock-朝の読書").firstMatch.exists)
        shot("46-sticky-paper-day")
    }
    func test22PinchTimelinePreservesTimeAndTasks() {
        launch()
        let task = app.otherElements["task-朝の読書"]
        let before = task.value as? String
        func zoom() -> Double { Double(zoomLabel().replacingOccurrences(of: "倍", with: "")) ?? 0 }
        pinch(1.6)
        XCTAssertGreaterThan(zoom(), 1.2)
        XCTAssertLessThan(zoom(), 2)
        pinch(0.5)
        XCTAssertEqual(zoom(), 1)
        for _ in 0..<4 { pinch(2) }
        XCTAssertEqual(zoom(), 8)
        pinch(0.5)
        XCTAssertLessThan(zoom(), 6)
        let retained = zoomLabel()
        let timeline = app.scrollViews["timeline"]
        timeline.swipeUp()
        let hour = (8...23).map { app.staticTexts[String(format: "%02d:00", $0)] }.first {
            $0.isHittable && $0.frame.minY >= timeline.frame.minY && $0.frame.maxY <= timeline.frame.maxY
        }
        XCTAssertNotNil(hour)
        let position = hour!.frame.minY
        selectTab("1日表示"); selectTab("計画")
        XCTAssertEqual(zoomLabel(), retained)
        XCTAssertEqual(hour!.frame.minY, position, accuracy: 3)
        XCTAssertEqual(task.value as? String, before)
    }

}
