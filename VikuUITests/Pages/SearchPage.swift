import XCTest

@MainActor
struct SearchPage {
    let app: XCUIApplication

    private var field: XCUIElement {
        app.searchFields.firstMatch
    }

    private var results: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH 'task.' AND identifier ENDSWITH '.title'",
        ))
    }

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
    }

    func search(for query: String) {
        field.tap()
        field.typeText(query)
    }

    func assertQuery(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(field.value as? String, expected, file: file, line: line)
    }

    func assertSingleResult(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = results.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(results.count, 1, file: file, line: line)
    }

    func openResult(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> TaskDetailPage {
        assertSingleResult(title, file: file, line: line)
        results.matching(NSPredicate(format: "label == %@", title)).firstMatch.tap()
        let page = TaskDetailPage(app: app)
        page.assertTaskTitle(title, file: file, line: line)
        return page
    }
}
