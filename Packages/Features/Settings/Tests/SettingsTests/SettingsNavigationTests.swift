@testable import Settings
import SwiftUI
import Testing
import VikuNavigation

@MainActor
struct SettingsNavigationTests {
    @Test(arguments: ["offline-mode", "quick-add-shortcuts", "push-notifications", "server-version-support"])
    func `returning from an article preserves the documentation index`(articleID: String) {
        let router = AppRouter()
        router.push(.documentationIndex)
        let indexPath = router.path

        router.push(.documentationArticle(articleID))
        #expect(router.path.count == 2)

        router.pop()
        #expect(router.path == indexPath)
    }

    @Test
    func `documentation and local Settings routes share one stack`() {
        let router = AppRouter()
        router.push(.documentationIndex)
        router.push(SettingsRoute.connections)
        #expect(router.path.count == 2)

        router.popToRoot()
        #expect(router.path.isEmpty)
    }
}
