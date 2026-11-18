import XCTest

@MainActor
final class TaskDetailCompletionTests: XCTestCase {
    func testCompletingOverdueTaskInDetailsUpdatesTodayOnReturn() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let today = application.launch()
        today.assertFixtureVisible()
        let title = "UI Test: Review overdue"

        let detail = today.openTask(title)
        detail.completeTask()
        let returnedToday = detail.backToToday()

        returnedToday.assertTaskVisible("UI Test: Plan today")
        returnedToday.assertTaskAbsent(title)
    }
}
