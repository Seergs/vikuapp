import XCTest

@MainActor
final class ScenarioLaunchTests: XCTestCase {
    func testUnauthenticatedScenarioOpensInstanceSetup() {
        let application = UITestApp()
        defer { application.terminate() }
        application.launch(scenario: .unauthenticated)
        XCTAssertTrue(application.app.staticTexts["Connect your instance"].waitForExistence(timeout: 10))
        XCTAssertFalse(application.app.tabBars.buttons["Home"].exists)
    }

    func testEmptyScenarioShowsHomeWithoutTasks() {
        let application = UITestApp()
        defer { application.terminate() }
        application.launch(scenario: .empty)
        XCTAssertTrue(application.app.staticTexts["Nothing due"].waitForExistence(timeout: 10))
    }

    func testCachedScenarioRestoresSQLiteOfflineAndFreshLaunchResetsIt() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let title = "UI Test: Remember this task"
        application.launch(scenario: .cached).assertFixtureVisible()

        createSyncedTask(title, id: 100, in: application, today: application.relaunch())

        let offline = application.relaunch(offline: true)
        offline.showTodayTasks()
        offline.assertTaskVisible(title)

        let resumed = application.relaunch()
        createSyncedTask("UI Test: Task after relaunch", id: 101, in: application, today: resumed)
        resumed.assertTaskVisible(title)

        let fresh = application.launch()
        fresh.assertFixtureVisible()
        fresh.assertTaskAbsent(title)
        createSyncedTask("UI Test: First task after reset", id: 100, in: application, today: fresh)
    }

    func testRelaunchKeepsPreferencesAndFreshLaunchResetsThem() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let navigation = AppPage(app: application.app)
        application.launch().assertFixtureVisible()
        navigation.showSettings().openAppearance().select(.dark)

        application.relaunch(offline: true).assertFixtureVisible()
        _ = navigation.showSettings().openAppearance()
        XCTAssertTrue(application.app.buttons["settings.appearance.option.dark"].isSelected)

        application.launch().assertFixtureVisible()
        _ = navigation.showSettings().openAppearance()
        XCTAssertTrue(application.app.buttons["settings.appearance.option.system"].isSelected)
    }

    private func createSyncedTask(_ title: String, id: Int, in application: UITestApp, today: TodayPage) {
        let quickAdd = AppPage(app: application.app).openQuickAdd()
        quickAdd.enterTitle(title)
        quickAdd.selectToday()
        quickAdd.submit()
        today.showTodayTasks()
        let syncedTitle = application.app.staticTexts["task.remote.\(id).title"]
        XCTAssertTrue(syncedTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(syncedTitle.label, title)
    }

    func testMultiAccountRelaunchKeepsActiveAccountAndItsOwnTasks() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch(scenario: .multiAccount).assertFixtureVisible()

        let app = application.app
        _ = AppPage(app: app).showSettings()
        let connections = app.buttons["Change"]
        XCTAssertTrue(connections.waitForExistence(timeout: 5))
        connections.tap()
        let secondAccount = app.buttons.containing(.staticText, identifier: "UI Test Second Account").firstMatch
        XCTAssertTrue(secondAccount.waitForExistence(timeout: 5))
        secondAccount.tap()

        let today = AppPage(app: app).showToday()
        let title = "UI Test: Second account task"
        today.assertTaskVisible(title)
        today.assertTaskAbsent("UI Test: Plan today")
        let relaunched = application.relaunch(offline: true)
        relaunched.assertTaskVisible(title)
        relaunched.assertTaskAbsent("UI Test: Plan today")
    }

    func testCapabilityLimitedScenarioShowsProjectListWithoutKanban() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch(scenario: .capabilityLimited).assertFixtureVisible()
        let app = application.app
        let project = AppPage(app: app).showProjects().openProject(id: 1, title: "UI Test Project")
        project.assertTaskVisible("UI Test: Plan today")
        XCTAssertFalse(app.buttons["Kanban"].exists)
    }
}
