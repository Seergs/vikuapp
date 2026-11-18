import XCTest

@MainActor
final class SearchTests: XCTestCase {
    func testSearchByTitleOpensMatchingTaskDetailsAndKeepsResultsOnReturn() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch().assertFixtureVisible()
        let search = AppPage(app: application.app).showSearch()
        let query = "Plan today"
        let title = "UI Test: Plan today"

        search.search(for: query)
        search.assertSingleResult(title)
        let detail = search.openResult(title)
        detail.assertNavigationMetadata(priority: "High")

        let returnedSearch = detail.backToSearch()
        returnedSearch.assertQuery(query)
        returnedSearch.assertSingleResult(title)
    }
}
