import XCTest

@MainActor
final class DuplicateTaskTests: XCTestCase {
    func testDuplicateFromDetailsShowsThePrefilledComposerAndOpensTheCopy() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let original = "UI Test: Plan today"
        let copy = "\(original) (copy)"
        let today = application.launch()
        let composer = today.openTask(original).openDuplicateComposer()

        composer.assertPrefilled(title: copy, project: "UI Test Project")
        composer.selectProject("UI Test Context Project")
        composer.submit()

        TaskDetailPage(app: application.app).assertTaskTitle(copy)
    }
}
