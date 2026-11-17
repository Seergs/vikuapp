import XCTest

@MainActor
final class QuickAddTests: XCTestCase {
    func testCreateFromTodayAppearsTodayAndInDefaultProject() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let today = application.launch()
        today.assertFixtureVisible()
        let navigation = AppPage(app: application.app)
        let title = "UI Test: Daily planning"

        let quickAdd = navigation.openQuickAdd()
        quickAdd.assertSelectedProject("UI Test Project")
        quickAdd.enterTitle(title)
        quickAdd.selectToday()
        quickAdd.submit()

        today.showTodayTasks()
        today.assertTaskVisible(title)
        let project = navigation.showProjects().openProject(id: 1, title: "UI Test Project")
        project.assertTaskVisible(title)
    }

    func testCreateFromProjectUsesContextInsteadOfDefaultProject() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch().assertFixtureVisible()
        let navigation = AppPage(app: application.app)
        let title = "UI Test: Context capture"
        let project = navigation.showProjects().openProject(id: 2, title: "UI Test Context Project")

        let quickAdd = navigation.openQuickAdd()
        quickAdd.assertSelectedProject("UI Test Context Project")
        quickAdd.enterTitle(title)
        quickAdd.assertNoDueDate()
        quickAdd.submit()

        project.assertTaskVisible(title)
        let defaultProject = project.backToProjects().openProject(id: 1, title: "UI Test Project")
        defaultProject.assertTaskVisible("UI Test: Plan today")
        defaultProject.assertTaskAbsent(title)
        let today = navigation.showToday()
        today.assertFixtureVisible()
        today.assertTaskAbsent(title)
    }
}
