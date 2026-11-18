import XCTest

@MainActor
struct CreateProjectPage {
    let app: XCUIApplication

    private var name: XCUIElement {
        app.textFields["project.create.name"]
    }

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(name.waitForExistence(timeout: 5), file: file, line: line)
    }

    func assertParent(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let parent = app.buttons["project.create.parent"]
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: parent)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed, file: file, line: line)
    }

    func enterName(_ title: String) {
        name.tap()
        name.typeText(title)
    }

    func save(file: StaticString = #filePath, line: UInt = #line) -> ProjectsPage {
        let save = app.buttons["project.create.save"]
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5), file: file, line: line)
        save.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), file: file, line: line)
        return ProjectsPage(app: app)
    }
}
