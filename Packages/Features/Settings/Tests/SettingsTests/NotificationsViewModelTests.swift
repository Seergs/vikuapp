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
            accountID: fakeAccountID,
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
    func `load populates the overdue tasks reminders time from the current user`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", overdueTasksRemindersTime: "14:30"))
        let viewModel = makeViewModel(userRepository: userRepository)

        await viewModel.load()

        #expect(viewModel.overdueTasksRemindersTime == "14:30")
    }

    @Test
    func `load populates the account time zone from the current user`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", timezone: "Europe/Madrid"))
        let viewModel = makeViewModel(userRepository: userRepository)

        await viewModel.load()

        #expect(viewModel.accountTimezone == "Europe/Madrid")
    }

    @Test
    func `load leaves the account time zone nil when the user has none set`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", timezone: nil))
        let viewModel = makeViewModel(userRepository: userRepository)

        await viewModel.load()

        #expect(viewModel.accountTimezone == nil)
    }

    @Test
    func `load keeps the default reminders time when the user has none set`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", overdueTasksRemindersTime: nil))
        let viewModel = makeViewModel(userRepository: userRepository)

        await viewModel.load()

        #expect(viewModel.overdueTasksRemindersTime == "09:00")
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

    // MARK: setOverdueTasksRemindersTime

    @Test
    func `setting the reminders time updates it and persists it to the user`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", overdueTasksRemindersTime: "09:00"))
        let viewModel = makeViewModel(userRepository: userRepository)
        await viewModel.load()

        await viewModel.setOverdueTasksRemindersTime("14:30")

        #expect(viewModel.overdueTasksRemindersTime == "14:30")
        #expect(userRepository.lastUpdatedOverdueTasksRemindersTime == "14:30")
    }

    @Test
    func `a failed reminders time update rolls back and shows A toast`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", overdueTasksRemindersTime: "09:00"))
        userRepository.updateError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = makeViewModel(userRepository: userRepository, toastPresenter: toastPresenter)
        await viewModel.load()

        await viewModel.setOverdueTasksRemindersTime("14:30")

        #expect(viewModel.overdueTasksRemindersTime == "09:00")
        #expect(toastPresenter.shownMessages.count == 1)
    }

    // MARK: setUserLevelEvent / setProject

    @Test
    func `enabling both user level events creates the user webhook with the user directed events`() async {
        let webhookRepository = FakeWebhookRepository()
        let viewModel = makeViewModel(webhookRepository: webhookRepository)
        await viewModel.confirmEnable()

        await viewModel.setUserLevelEvent(.taskOverdue, isEnabled: true)
        await viewModel.setUserLevelEvent(.taskReminderFired, isEnabled: true)

        #expect(viewModel.settings.userLevelEvents == WebhookEvent.userDirected)
        #expect(webhookRepository.createdUserWebhooks.count == 1)
        #expect(webhookRepository.createdUserWebhooks[0].secret == "test-secret")
        #expect(webhookRepository.updatedUserWebhooks.count == 1)
        #expect(Set(webhookRepository.updatedUserWebhooks[0].events) == WebhookEvent.userDirected)
    }

    @Test
    func `enabling a single user level event only subscribes to that event`() async {
        let webhookRepository = FakeWebhookRepository()
        let viewModel = makeViewModel(webhookRepository: webhookRepository)
        await viewModel.confirmEnable()

        await viewModel.setUserLevelEvent(.taskOverdue, isEnabled: true)

        #expect(viewModel.settings.userLevelEvents == [.taskOverdue])
        #expect(webhookRepository.createdUserWebhooks.count == 1)
        #expect(webhookRepository.createdUserWebhooks[0].events == [.taskOverdue])
    }

    @Test
    func `selecting a project's first event creates its webhook with just that event`() async {
        let project = Project(id: 4, title: "Work")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()

        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)

        #expect(viewModel.settings.events(for: project.id) == [.taskCreated])
        #expect(webhookRepository.createdProjectWebhooks.count == 1)
        #expect(webhookRepository.createdProjectWebhooks[0].projectID == 4)
        #expect(webhookRepository.createdProjectWebhooks[0].events == [.taskCreated])
    }

    @Test
    func `customizing a project's events updates its webhook independently of other projects`() async {
        let projectA = Project(id: 1, title: "A")
        let projectB = Project(id: 2, title: "B")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [projectA, projectB])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: projectA)
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: projectB)

        await viewModel.setProjectEvent(.taskDeleted, isEnabled: true, for: projectA)
        await viewModel.setProjectEvent(.taskCreated, isEnabled: false, for: projectA)

        #expect(viewModel.settings.events(for: projectA.id) == [.taskDeleted])
        #expect(viewModel.settings.events(for: projectB.id) == [.taskCreated])
        #expect(webhookRepository.updatedProjectWebhooks.last?.webhook.projectID == 1)
    }

    @Test
    func `unchecking a project's only event deletes only that project's webhook`() async {
        let projectA = Project(id: 1, title: "A")
        let projectB = Project(id: 2, title: "B")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [projectA, projectB])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: projectA)
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: projectB)

        await viewModel.setProjectEvent(.taskCreated, isEnabled: false, for: projectA)

        #expect(viewModel.settings.events(for: projectA.id).isEmpty)
        #expect(viewModel.settings.events(for: projectB.id) == [.taskCreated])
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

        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)

        #expect(viewModel.settings.events(for: project.id) == [.taskCreated])
        #expect(webhookRepository.createdProjectWebhooks.isEmpty)
    }

    // MARK: setProjectEvents / disableProjectWebhook

    @Test
    func `setProjectEvents replaces a project's whole selection in one sync call`() async {
        let project = Project(id: 4, title: "Work")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()

        await viewModel.setProjectEvents([.taskCreated, .taskDeleted], for: project)

        #expect(viewModel.settings.events(for: project.id) == [.taskCreated, .taskDeleted])
        #expect(webhookRepository.createdProjectWebhooks.count == 1)
        #expect(Set(webhookRepository.createdProjectWebhooks[0].events) == [.taskCreated, .taskDeleted])
    }

    @Test
    func `disableProjectWebhook clears the project's events and deletes its webhook`() async {
        let project = Project(id: 4, title: "Work")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)

        await viewModel.disableProjectWebhook(project)

        #expect(viewModel.settings.events(for: project.id).isEmpty)
        #expect(webhookRepository.deletedProjectWebhookIDs.map(\.projectID) == [4])
    }

    // MARK: otherWebhooks

    @Test
    func `otherWebhooks excludes only this device's own webhook`() async throws {
        let project = Project(id: 4, title: "Work")
        let ourTargetURL = try #require(URL(string: "https://relay.example.com/h/device-1"))
        let theirWebhook = try Webhook(
            id: 999, targetURL: #require(URL(string: "https://hooks.slack.com/services/x")),
            events: [.taskCreated], projectID: project.id,
        )
        let webhookRepository = FakeWebhookRepository(projectWebhooks: [project.id: [theirWebhook]])
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)

        let others = await viewModel.otherWebhooks(for: project.id)

        #expect(others.map(\.id) == [999])
        #expect(others.allSatisfy { $0.targetURL != ourTargetURL })
    }

    @Test
    func `otherWebhooks returns everything when this device was never registered`() async throws {
        let project = Project(id: 4, title: "Work")
        let theirWebhook = try Webhook(
            id: 999, targetURL: #require(URL(string: "https://hooks.slack.com/services/x")),
            events: [.taskCreated], projectID: project.id,
        )
        let webhookRepository = FakeWebhookRepository(projectWebhooks: [project.id: [theirWebhook]])
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()

        let others = await viewModel.otherWebhooks(for: project.id)

        #expect(others.map(\.id) == [999])
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
        await viewModel.setUserLevelEvent(.taskOverdue, isEnabled: true)
        await viewModel.setUserLevelEvent(.taskReminderFired, isEnabled: true)
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)

        await viewModel.disable()

        #expect(viewModel.settings.isEnabled == false)
        #expect(webhookRepository.deletedUserWebhookIDs.count == 1)
        #expect(webhookRepository.deletedProjectWebhookIDs.map(\.projectID) == [4])
        #expect(registering.disableCallCount == 1)
        #expect(store.savedSettings.last?.isEnabled == false)
        // The toggles reset along with the master switch — see the next test.
        #expect(viewModel.settings.userLevelEvents.isEmpty)
        #expect(viewModel.settings.events(for: project.id).isEmpty)
    }

    @Test
    func `re enabling after a disable starts from a clean slate instead of recreating what was on before`() async {
        let project = Project(id: 4, title: "Work")
        let webhookRepository = FakeWebhookRepository()
        let projectRepository = FakeProjectRepository(projects: [project])
        let viewModel = makeViewModel(webhookRepository: webhookRepository, projectRepository: projectRepository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setUserLevelEvent(.taskOverdue, isEnabled: true)
        await viewModel.setUserLevelEvent(.taskReminderFired, isEnabled: true)
        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)
        await viewModel.disable()
        let userCreatesBeforeReenable = webhookRepository.createdUserWebhooks.count
        let projectCreatesBeforeReenable = webhookRepository.createdProjectWebhooks.count

        await viewModel.confirmEnable()

        #expect(viewModel.settings.isEnabled)
        #expect(viewModel.settings.userLevelEvents.isEmpty)
        #expect(viewModel.settings.events(for: project.id).isEmpty)
        // Re-enabling alone creates no new webhooks: nothing is selected
        // until the user opts back in to each one explicitly.
        #expect(webhookRepository.createdUserWebhooks.count == userCreatesBeforeReenable)
        #expect(webhookRepository.createdProjectWebhooks.count == projectCreatesBeforeReenable)
    }
}
