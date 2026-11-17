import XCTest

@MainActor
final class ScaffoldingTests: XCTestCase {
    func testLaunchShowsAuthenticatedTodayFixture() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch().assertFixtureVisible()
    }

    func testRelaunchResetsLocalAndFakeServerState() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        let today = application.launch()
        today.assertFixtureVisible()
        today.completeOverdueTask()
        application.terminate()
        application.launch().assertFixtureVisible()
    }
}
