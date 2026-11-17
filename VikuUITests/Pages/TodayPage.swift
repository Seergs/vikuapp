import XCTest

/// All queries for Today live here; tests describe user actions and outcomes.
@MainActor
struct TodayPage {
    let app: XCUIApplication

    private var plannedTaskTitle: XCUIElement {
        app.staticTexts["task.remote.1.title"]
    }

    private var overdueTaskTitle: XCUIElement {
        app.staticTexts["task.remote.2.title"]
    }

    private var overdueTaskCompletion: XCUIElement {
        app.buttons["task.remote.2.completion"]
    }

    func assertFixtureVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(plannedTaskTitle.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(plannedTaskTitle.label, "UI Test: Plan today", file: file, line: line)
        XCTAssertTrue(overdueTaskTitle.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(overdueTaskTitle.label, "UI Test: Review overdue", file: file, line: line)
    }

    func showTodayTasks(file: StaticString = #filePath, line: UInt = #line) {
        let filter = app.buttons["home.filter.today"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), file: file, line: line)
        filter.tap()
    }

    func assertTaskVisible(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(taskTitle(title).firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(taskTitle(title).count, 1, file: file, line: line)
    }

    func assertTaskAbsent(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(taskTitle(title).firstMatch.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    private func taskTitle(_ title: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier ENDSWITH '.title'", title))
    }

    func openTask(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> TaskDetailPage {
        let row = taskTitle(title).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
        row.tap()
        let page = TaskDetailPage(app: app)
        page.assertTaskTitle(title, file: file, line: line)
        return page
    }

    func completeOverdueTask(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(overdueTaskCompletion.waitForExistence(timeout: 5), file: file, line: line)
        overdueTaskCompletion.tap()
        XCTAssertTrue(overdueTaskTitle.waitForNonExistence(timeout: 5), file: file, line: line)
    }
}
