import XCTest

@MainActor
final class TaskDetailNavigationTests: XCTestCase {
    func testDetailMetadataSurvivesEditingAndReturningFromToday() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let today = application.launch()
        today.assertFixtureVisible()
        let title = "UI Test: Plan today"

        let detail = today.openTask(title)
        detail.assertNavigationMetadata(priority: "High")
        detail.selectLowPriority()
        detail.assertNavigationMetadata(priority: "Low")
        let returnedToday = detail.backToToday()
        returnedToday.assertFixtureVisible()

        let reopenedDetail = returnedToday.openTask(title)
        reopenedDetail.assertNavigationMetadata(priority: "Low")
        reopenedDetail.backToToday().assertFixtureVisible()
    }
}
