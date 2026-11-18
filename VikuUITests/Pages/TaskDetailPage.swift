import XCTest

@MainActor
struct TaskDetailPage {
    let app: XCUIApplication

    private var completion: XCUIElement {
        app.buttons["taskDetail.completion"]
    }

    func assertTaskTitle(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts["taskDetail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(title.label, expected, file: file, line: line)
    }

    func assertNavigationMetadata(priority: String, file: StaticString = #filePath, line: UInt = #line) {
        let dueDate = app.buttons["taskDetail.dueDate"]
        XCTAssertTrue(dueDate.waitForExistence(timeout: 5), file: file, line: line)
        // ICU uses a narrow no-break space before AM/PM on some OS versions.
        let dueDateValue = (dueDate.value as? String)?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        XCTAssertEqual(dueDateValue, "Today, 12:00 PM", file: file, line: line)
        let priorityRow = app.buttons["taskDetail.priority"]
        XCTAssertTrue(priorityRow.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(priorityRow.value as? String, priority, file: file, line: line)
        let label = app.staticTexts["taskDetail.label.remote.1"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(label.label, "UI Test Navigation", file: file, line: line)
    }

    func selectLowPriority(file: StaticString = #filePath, line: UInt = #line) {
        let priority = app.buttons["taskDetail.priority"]
        XCTAssertTrue(priority.waitForExistence(timeout: 5), file: file, line: line)
        priority.tap()
        let low = app.buttons["taskDetail.priority.1"]
        XCTAssertTrue(low.waitForExistence(timeout: 5), file: file, line: line)
        low.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Low'"), object: priority)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed, file: file, line: line)
    }

    func completeTask(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(completion.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(completion.label, "Mark as Done", file: file, line: line)
        completion.tap()
        XCTAssertTrue(
            completion.wait(for: \.label, toEqual: "Mark as Not Done", timeout: 5),
            file: file, line: line,
        )
    }

    func backToToday(file: StaticString = #filePath, line: UInt = #line) -> TodayPage {
        let back = app.navigationBars["Task Details"].buttons["Today"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), file: file, line: line)
        back.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5), file: file, line: line)
        return TodayPage(app: app)
    }
}
