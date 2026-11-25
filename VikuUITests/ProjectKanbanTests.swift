import XCTest

@MainActor
final class ProjectKanbanTests: XCTestCase {
    func testSelectingAnotherBoardReplacesItsColumns() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch()
        let app = application.app
        let projects = AppPage(app: app).showProjects()
        _ = projects.openProject(title: "UI Test Project")

        let kanban = app.buttons["Kanban"]
        XCTAssertTrue(kanban.waitForExistence(timeout: 5))
        kanban.tap()
        let sprint = app.staticTexts["Sprint queue"]
        XCTAssertTrue(sprint.waitForExistence(timeout: 10))

        let selector = app.buttons["kanban.boardSelector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Kanban boards"].firstMatch.waitForExistence(timeout: 5))
        let support = app.buttons["Support"]
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        support.tap()

        XCTAssertTrue(app.staticTexts["Support inbox"].waitForExistence(timeout: 10))
        XCTAssertTrue(sprint.waitForNonExistence(timeout: 5))
    }
}
