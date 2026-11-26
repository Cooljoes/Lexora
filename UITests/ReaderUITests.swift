import XCTest
import UIKit

final class ReaderUITests: XCTestCase {
    private func launch(contentSize: UIContentSizeCategory? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
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
        attach("书桌")
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
        attach("离线词条")
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
        if UIDevice.current.userInterfaceIdiom == .pad {
            tapSection("书桌", app)
            app.buttons["全部"].tap()
            XCTAssertTrue(app.navigationBars["阅读历史"].waitForExistence(timeout: 6), app.debugDescription)
            XCTAssertTrue(recent.isHittable)
        }
    }
    func testClassicSelection() {
        let app = launch()
        app.buttons["featuredReading"].tap()
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'focus-'")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        attach("精读")
    }
    func testFocusWordsFitAtAccessibilitySize() throws {
        let app = launch(contentSize: .accessibilityExtraLarge)
        let featured = app.buttons["featuredReading"]
        XCTAssertTrue(featured.waitForExistence(timeout: 10))
        attach("大字号书桌")
        featured.tap()

        let reader = app.scrollViews.containing(.staticText, identifier: "英文原文").firstMatch
        let words = reader.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'focus-'"))
        XCTAssertTrue(words.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        let chips = words.allElementsBoundByIndex
        XCTAssertEqual(chips.count, 6)
        for chip in chips {
            // Only scroll vertically. A chip clipped off the trailing edge must fail.
            for _ in 0..<12 {
                if chip.isHittable { break }
                reader.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(chip.isHittable, chip.identifier)
            XCTAssertGreaterThan(chip.frame.width, 0)
            XCTAssertGreaterThanOrEqual(chip.frame.minX, reader.frame.minX - 1, chip.identifier)
            XCTAssertLessThanOrEqual(chip.frame.maxX, reader.frame.maxX + 1, chip.identifier)
        }
        attach("大字号重点词")
        let last = try XCTUnwrap(chips.last)
        let lemma = String(last.identifier.dropFirst("focus-".count))
        last.tap()
        XCTAssertTrue(app.staticTexts[lemma].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        let definition = app.staticTexts["语境候选释义"]
        XCTAssertTrue(definition.waitForExistence(timeout: 6))
        XCTAssertTrue(definition.isHittable, "大字号词条打开后应直接看到释义")
        attach("大字号词条")
        let sentence = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "文中原句")).firstMatch
        let detail = app.scrollViews.containing(.staticText, identifier: "语境候选释义").firstMatch
        for _ in 0..<12 {
            if sentence.isHittable { break }
            detail.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(sentence.isHittable)
        sentence.tap()
        XCTAssertTrue(detail.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'There is grandeur'")).firstMatch.exists)
    }
    func testHistorySearchWithNoMatches() {
        let app = launch()
        app.buttons["featuredReading"].tap()
        XCTAssertTrue(app.staticTexts["英文原文"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        tapSection("历史", app)
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "物种起源").firstMatch.waitForExistence(timeout: 8))
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        if !search.isHittable {
            let reveal = app.buttons.matching(NSPredicate(format: "label IN %@", ["搜索", "Search"])).firstMatch
            if reveal.exists { reveal.tap() }
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("zzzxqv")
        XCTAssertTrue(app.staticTexts["未找到相关记录"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testUnregionalizedIPAAndSenseSelection() {
        let app = launch()
        tapSection("生词本", app)
        let search = app.textFields["wordSearch"]
        search.tap()
        search.typeText("adagio")
        app.buttons["dictionaryLookup"].tap()
        let ipa = app.staticTexts["generalIPA"]
        XCTAssertTrue(ipa.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(ipa.label.contains("/əˈdɑːd͡ʒiəʊ/"), ipa.label)
        let source = app.descendants(matching: .any).matching(identifier: "generalIPASource").firstMatch
        XCTAssertTrue(source.label.contains("English Wiktionary"), source.label)

        let picker = app.buttons["sensePicker"]
        picker.tap()
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sense-'"))
        let other = options.matching(NSPredicate(format: "selected == false")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), app.debugDescription)
        let newSelection = other.identifier
        other.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
        picker.tap()
        XCTAssertTrue(app.buttons[newSelection].isSelected)
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
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
