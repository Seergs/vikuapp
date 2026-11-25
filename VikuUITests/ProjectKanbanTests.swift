import XCTest

@MainActor
final class ProjectKanbanTests: XCTestCase {
    func testRestoringSavedFilterWaitsToShowSearchUntilTheBoardCanOpen() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch()
        let app = application.app
        openSavedFilter(in: app)
        let kanban = app.buttons["Kanban"]
        XCTAssertTrue(kanban.waitForExistence(timeout: 5))
        kanban.tap()
        let filterQueue = app.staticTexts["Filter queue"]
        XCTAssertTrue(filterQueue.waitForExistence(timeout: 10))

        application.terminate()
        application.launch(preservingPreferences: true, slowReachability: true)
        openSavedFilter(in: app)
        XCTAssertFalse(filterQueue.exists)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertTrue(filterQueue.waitForExistence(timeout: 10))
    }

    private func openSavedFilter(in app: XCUIApplication) {
        _ = AppPage(app: app).showProjects()
        let title = "UI Test Saved Filter"
        let filter = app.buttons[title]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    func testProjectRemembersBoardAndListAcrossLaunches() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch()
        let app = application.app
        let projects = AppPage(app: app).showProjects()
        let project = projects.openProject(title: "UI Test Project")
        project.assertTaskVisible("UI Test: Plan today")

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

        let supportInbox = app.staticTexts["Support inbox"]
        XCTAssertTrue(supportInbox.waitForExistence(timeout: 10))
        XCTAssertTrue(sprint.waitForNonExistence(timeout: 5))

        let projectsAgain = project.backToProjects()
        let otherProject = projectsAgain.openProject(title: "UI Test Context Project")
        XCTAssertFalse(selector.exists)
        _ = otherProject.backToProjects().openProject(title: "UI Test Project")
        XCTAssertTrue(supportInbox.waitForExistence(timeout: 10))

        application.terminate()
        application.launch(preservingPreferences: true)
        _ = AppPage(app: app).showProjects().openProject(title: "UI Test Project")
        XCTAssertTrue(supportInbox.waitForExistence(timeout: 10))
        app.buttons["List"].tap()
        XCTAssertTrue(supportInbox.waitForNonExistence(timeout: 5))

        application.terminate()
        application.launch(preservingPreferences: true)
        let reopened = AppPage(app: app).showProjects().openProject(title: "UI Test Project")
        reopened.assertTaskVisible("UI Test: Plan today")
        XCTAssertFalse(selector.exists)
    }
}
