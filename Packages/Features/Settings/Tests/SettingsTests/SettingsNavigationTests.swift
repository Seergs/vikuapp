@testable import Settings
import SwiftUI
import Testing
import VikuNavigation
import VikunjaCore

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
    func `returning from the Magic guide preserves the mode selection screen`() {
        let router = AppRouter()
        router.push(SettingsRoute.quickAddMagic)
        let pickerPath = router.path

        router.push(.documentationArticle("quick-add-shortcuts"))
        #expect(router.path.count == 2)

        router.pop()
        #expect(router.path == pickerPath)
    }

    @Test(arguments: [false, true])
    func `project screens return through the project landing screen`(opensDetails: Bool) {
        let project = Project(id: 4, title: "Work")
        let router = AppRouter()
        router.push(SettingsRoute.notifications)
        let notificationsPath = router.path
        router.push(SettingsRoute.projectNotifications(project))
        let projectPath = router.path

        router.push(opensDetails
            ? SettingsRoute.projectNotificationDetails(project)
            : SettingsRoute.projectNotificationEvents(project))
        #expect(router.path.count == 3)

        router.pop()
        #expect(router.path == projectPath)
        router.pop()
        #expect(router.path == notificationsPath)
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
