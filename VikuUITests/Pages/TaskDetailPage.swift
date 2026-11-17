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
