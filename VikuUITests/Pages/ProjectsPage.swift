import XCTest

@MainActor
struct ProjectsPage {
    let app: XCUIApplication

    func openProject(id: Int, title: String, file: StaticString = #filePath, line: UInt = #line) -> ProjectPage {
        let row = app.descendants(matching: .any).matching(identifier: "project.remote.\(id)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
        row.tap()
        let page = ProjectPage(app: app, title: title)
        page.assertVisible(file: file, line: line)
        return page
    }
}

@MainActor
struct ProjectPage {
    let app: XCUIApplication
    let title: String

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), file: file, line: line)
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

    func backToProjects(file: StaticString = #filePath, line: UInt = #line) -> ProjectsPage {
        let back = app.navigationBars.buttons["Projects"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), file: file, line: line)
        back.tap()
        return ProjectsPage(app: app)
    }
}
