import XCTest

final class ReaderUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launch()
        return app
    }
    private func tapSection(_ section: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[section]
        if tab.exists { tab.tap() }
        else {
            let button = app.buttons[section].firstMatch
            if !button.isHittable {
                let toggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar' OR label CONTAINS '边栏'")).firstMatch
                if toggle.exists { toggle.tap() }
            }
            XCTAssertTrue(button.waitForExistence(timeout: 8), app.debugDescription)
            button.tap()
        }
    }
    func testDeskAndOfflineWordbook() {
        let app = launch()
        XCTAssertTrue(app.buttons["featuredReading"].waitForExistence(timeout: 15), app.debugDescription)
        attach("书桌", app)
        tapSection("生词本", app)
        let search = app.textFields["wordSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 6))
        search.tap()
        search.typeText("hospital")
        app.buttons["dictionaryLookup"].tap()
        XCTAssertTrue(app.buttons["播放英式发音"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["播放美式发音"].exists)
        app.buttons["播放英式发音"].tap()
        let favorite = app.buttons["toggleFavorite"]
        if favorite.label == "取消收藏" { favorite.tap() }
        favorite.tap()
        XCTAssertEqual(favorite.label, "取消收藏")
        attach("离线词条", app)
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        tapSection("生词本", app)
        let saved = app.buttons.containing(.staticText, identifier: "hospital").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8), app.debugDescription)
        saved.tap()
        app.buttons["toggleFavorite"].tap()
        app.buttons["完成"].tap()
    }
    func testComposeReadAndReopenHistory() {
        let app = launch()
        app.buttons["输入原文"].tap()
        let editor = app.textViews["sourceInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 6))
        editor.tap()
        editor.typeText("The birds rested beside the beautiful river.")
        app.buttons["开始精读"].tap()
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 8), app.debugDescription)
        let word = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'focus-'")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 8), app.debugDescription)
        word.tap()
        XCTAssertTrue(app.buttons["toggleFavorite"].waitForExistence(timeout: 8))
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        tapSection("历史", app)
        let recent = app.buttons.containing(.staticText, identifier: "The birds rested beside the beautiful river.").firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 8), app.debugDescription)
        recent.tap()
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 8))
    }
    func testClassicSelection() {
        let app = launch()
        app.buttons["featuredReading"].tap()
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'focus-'")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        attach("精读", app)
    }
    func testSystemCopyAndPaste() {
        let app = launch()
        app.buttons["featuredReading"].tap()
        app.buttons["分享原文"].tap()
        let copy = app.cells.matching(NSPredicate(format: "label IN %@", ["拷贝", "复制", "Copy"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        copy.tap()
        app.terminate()
        app.launch()
        app.buttons["粘贴英文"].tap()
        let pastePrompt = app.buttons.matching(NSPredicate(format: "label IN %@", ["允许粘贴", "Allow Paste"])).firstMatch
        if pastePrompt.exists { pastePrompt.tap() }
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["物种起源"].exists)
    }
    func testSystemShareExtension() {
        let app = launch()
        app.buttons["featuredReading"].tap()
        app.buttons["分享原文"].tap()
        let share = app.cells.matching(NSPredicate(format: "label IN %@", ["Lexora", "存入 Lexora"])).firstMatch
        if !share.waitForExistence(timeout: 3) {
            let more = app.cells.matching(NSPredicate(format: "label IN %@", ["更多", "More"])).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 6), app.debugDescription)
            more.tap()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 8), app.debugDescription)
        share.tap()
        let editor = app.textViews["sharedTextInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 45), app.debugDescription)
        let ready = NSPredicate(format: "value CONTAINS %@", "There is grandeur")
        expectation(for: ready, evaluatedWith: editor)
        waitForExpectations(timeout: 12)
        XCTAssertTrue((editor.value as? String)?.contains("There is grandeur") == true)
        app.buttons["存入"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 20), app.debugDescription)
        app.terminate()
        app.launch()
        tapSection("历史", app)
        let incoming = app.buttons.containing(.staticText, identifier: "系统分享").firstMatch
        XCTAssertTrue(incoming.waitForExistence(timeout: 8), app.debugDescription)
        incoming.tap()
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 8))
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
