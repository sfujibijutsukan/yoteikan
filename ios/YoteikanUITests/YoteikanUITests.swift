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
        XCTAssertTrue(app.staticTexts["presetAdded"].exists); shot("02-presets")
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
        XCTAssertTrue(app.staticTexts["overlapWarning"].waitForExistence(timeout: 3))
        XCTAssertEqual(task.value as? String, "09:30|60")
        XCTAssertEqual(app.otherElements["task-朝の読書"].value as? String, "08:00|30")
        shot("04-overlap-after-drag")
        app.buttons["undoButton"].tap()
        let handle = app.otherElements["resize-資料作成"]
        XCTAssertTrue(handle.exists)
        let point = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(forDuration: 0.15, thenDragTo: point.withOffset(CGVector(dx: 0, dy: 46.5)))
        XCTAssertTrue(app.staticTexts["overlapWarning"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["calendarConnected"].waitForExistence(timeout: 8))
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
}
