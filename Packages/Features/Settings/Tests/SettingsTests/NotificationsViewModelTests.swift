import Foundation
@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct NotificationsViewModelTests {
    private func makeViewModel(
        webhookRepository: FakeWebhookRepository = FakeWebhookRepository(),
        projectRepository: FakeProjectRepository = FakeProjectRepository(),
        userRepository: FakeUserRepository = FakeUserRepository(),
        pushNotificationRegistering: FakePushNotificationRegistering = FakePushNotificationRegistering(),
        notificationSettingsStore: FakeNotificationSettingsStore = FakeNotificationSettingsStore(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
    ) -> NotificationsViewModel {
        NotificationsViewModel(
            webhookRepository: webhookRepository,
            projectRepository: projectRepository,
            userRepository: userRepository,
            pushNotificationRegistering: pushNotificationRegistering,
            notificationSettingsStore: notificationSettingsStore,
            toastPresenter: toastPresenter,
        )
    }

    // MARK: load

    @Test
    func `load populates projects and leaves the feature untouched when it was never enabled`() async {
        let projectRepository = FakeProjectRepository(projects: [Project(id: 1, title: "Inbox")])
        let registering = FakePushNotificationRegistering()
        let viewModel = makeViewModel(projectRepository: projectRepository, pushNotificationRegistering: registering)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.projects.map(\.title) == ["Inbox"])
        #expect(registering.enabledUserIDs.isEmpty)
        #expect(viewModel.isPermissionDenied == false)
    }

    @Test
    func `load re checks permission and flags it denied when it was enabled but is no longer granted`() async {
        let store = FakeNotificationSettingsStore(settings: NotificationSettings(isEnabled: true))
        let registering = FakePushNotificationRegistering()
        registering.enableResult = .success(nil)
        let viewModel = makeViewModel(pushNotificationRegistering: registering, notificationSettingsStore: store)

        await viewModel.load()

        #expect(viewModel.isPermissionDenied)
        #expect(registering.enabledUserIDs == [1])
    }

    @Test
    func `load surfaces A friendly message on a project fetch failure`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.fetchError = .network("offline")
        let viewModel = makeViewModel(projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
    }

    // MARK: confirmEnable

    @Test
    func `confirming enable persists isEnabled once the relay registration succeeds`() async {
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(notificationSettingsStore: store)

        await viewModel.confirmEnable()

        #expect(viewModel.settings.isEnabled)
        #expect(store.savedSettings.last?.isEnabled == true)
        #expect(viewModel.isPermissionDenied == false)
    }

    @Test
    func `confirming enable with denied permission leaves the feature off`() async {
        let store = FakeNotificationSettingsStore()
        let registering = FakePushNotificationRegistering()
        registering.enableResult = .success(nil)
        let viewModel = makeViewModel(pushNotificationRegistering: registering, notificationSettingsStore: store)

        await viewModel.confirmEnable()

        #expect(viewModel.settings.isEnabled == false)
        #expect(viewModel.isPermissionDenied)
        #expect(store.savedSettings.isEmpty)
    }

    // MARK: setUserLevelEnabled / setProject

    @Test
    func `enabling user level notifications creates the user webhook with the user directed events`() async {
        let webhookRepository = FakeWebhookRepository()
        let viewModel = makeViewModel(webhookRepository: webhookRepository)
        await viewModel.confirmEnable()

        await viewModel.setUserLevelEnabled(true)

        #expect(viewModel.settings.userLevelEnabled)
        #expect(webhookRepository.createdUserWebhooks.count == 1)
        #expect(Set(webhookRepository.createdUserWebhooks[0].events) == WebhookEvent.userDirected)
        #expect(webhookRepository.createdUserWebhooks[0].secret == "test-secret")
    }

    @Test
    func `enabling a project creates its webhook with the default project events`() async {
        let project = Project(id: 4, title: "Work")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()

        await viewModel.setProject(project, isEnabled: true)

        #expect(viewModel.settings.enabledProjectIDs == [4])
        #expect(webhookRepository.createdProjectWebhooks.count == 1)
        #expect(webhookRepository.createdProjectWebhooks[0].projectID == 4)
        #expect(Set(webhookRepository.createdProjectWebhooks[0].events) == NotificationSettings.defaultProjectEvents)
    }

    @Test
    func `disabling a project deletes only that project's webhook`() async {
        let projectA = Project(id: 1, title: "A")
        let projectB = Project(id: 2, title: "B")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [projectA, projectB])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProject(projectA, isEnabled: true)
        await viewModel.setProject(projectB, isEnabled: true)

        await viewModel.setProject(projectA, isEnabled: false)

        #expect(viewModel.settings.enabledProjectIDs == [2])
        #expect(webhookRepository.deletedProjectWebhookIDs.map(\.projectID) == [1])
        #expect(webhookRepository.projectWebhooks[2]?.count == 1)
    }

    @Test
    func `changing settings while disabled only persists, with no server calls`() async {
        let webhookRepository = FakeWebhookRepository()
        let project = Project(id: 4, title: "Work")
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()

        await viewModel.setProject(project, isEnabled: true)

        #expect(viewModel.settings.enabledProjectIDs == [4])
        #expect(webhookRepository.createdProjectWebhooks.isEmpty)
    }

    // MARK: disable

    @Test
    func `disabling deletes every webhook this device created and unregisters from the relay`() async {
        let project = Project(id: 4, title: "Work")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [project])
        let registering = FakePushNotificationRegistering()
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(
            webhookRepository: webhookRepository,
            projectRepository: projectRepository,
            pushNotificationRegistering: registering,
            notificationSettingsStore: store,
        )
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setUserLevelEnabled(true)
        await viewModel.setProject(project, isEnabled: true)

        await viewModel.disable()

        #expect(viewModel.settings.isEnabled == false)
        #expect(webhookRepository.deletedUserWebhookIDs.count == 1)
        #expect(webhookRepository.deletedProjectWebhookIDs.map(\.projectID) == [4])
        #expect(registering.disableCallCount == 1)
        #expect(store.savedSettings.last?.isEnabled == false)
    }
}
