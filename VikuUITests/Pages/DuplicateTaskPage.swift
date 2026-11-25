import XCTest

@MainActor
struct DuplicateTaskPage {
    let app: XCUIApplication

    private var project: XCUIElement {
        app.buttons["duplicateTask.project"]
    }

    func assertPrefilled(title expected: String, project expectedProject: String, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.descendants(matching: .any)["duplicateTask.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(title.value as? String, expected, file: file, line: line)
        XCTAssertEqual(project.value as? String, expectedProject, file: file, line: line)
        XCTAssertTrue(app.switches["Copy labels"].exists, file: file, line: line)
        XCTAssertFalse(app.navigationBars["Duplicate Task"].exists, file: file, line: line)
    }

    func selectProject(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(project.wait(for: \.isEnabled, toEqual: true, timeout: 5), file: file, line: line)
        project.tap()

        let destination = app.buttons[name]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), file: file, line: line)
        destination.tap()

        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name), object: project)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, file: file, line: line)
    }

    func submit(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["duplicateTask.submit"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap()
    }
}
