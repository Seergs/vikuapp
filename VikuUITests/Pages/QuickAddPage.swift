import XCTest

@MainActor
struct QuickAddPage {
    let app: XCUIApplication

    private var title: XCUIElement {
        app.textViews["quickAdd.title"]
    }

    private var project: XCUIElement {
        app.buttons["quickAdd.project"]
    }

    private var dueDate: XCUIElement {
        app.buttons["quickAdd.dueDate"]
    }

    private var create: XCUIElement {
        app.buttons["quickAdd.create"]
    }

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(title.waitForExistence(timeout: 5), file: file, line: line)
    }

    func assertSelectedProject(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate(format: "value == %@ AND enabled == true", expected)
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: project)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, file: file, line: line)
    }

    func enterTitle(_ text: String) {
        title.tap()
        title.typeText(text)
    }

    func selectToday(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(dueDate.waitForExistence(timeout: 5), file: file, line: line)
        // An empty draft opens the calendar on today. Saving explicitly applies it.
        dueDate.tap()
        DueDatePage(app: app).saveCurrentDate(file: file, line: line)
        XCTAssertTrue(title.waitForExistence(timeout: 5), file: file, line: line)
    }

    func assertNoDueDate(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(dueDate.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue((dueDate.value as? String ?? "").isEmpty, file: file, line: line)
    }

    func submit(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(create.wait(for: \.isEnabled, toEqual: true, timeout: 5), file: file, line: line)
        create.tap()
        XCTAssertTrue(create.waitForNonExistence(timeout: 5), file: file, line: line)
    }
}

@MainActor
struct DueDatePage {
    let app: XCUIApplication

    func saveCurrentDate(file: StaticString = #filePath, line: UInt = #line) {
        let save = app.buttons["dueDate.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), file: file, line: line)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), file: file, line: line)
    }
}
