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

    func completeOverdueTask(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(overdueTaskCompletion.waitForExistence(timeout: 5), file: file, line: line)
        overdueTaskCompletion.tap()
        XCTAssertTrue(overdueTaskTitle.waitForNonExistence(timeout: 5), file: file, line: line)
    }
}
