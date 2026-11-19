import Foundation
@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct ProjectNotificationSettingsTests {
    private let project = Project(id: 4, title: "Work")
    private let otherProject = Project(id: 5, title: "Home")

    private func makeViewModel(
        repository: FakeWebhookRepository = FakeWebhookRepository(),
        store: FakeNotificationSettingsStore = FakeNotificationSettingsStore(),
        toast: FakeToastPresenter = FakeToastPresenter(),
    ) -> NotificationsViewModel {
        NotificationsViewModel(
            accountID: fakeAccountID,
            webhookRepository: repository,
            projectRepository: FakeProjectRepository(projects: [project, otherProject]),
            userRepository: FakeUserRepository(),
            pushNotificationRegistering: FakePushNotificationRegistering(),
            notificationSettingsStore: store,
            groupOverdueNotificationsStore: FakeGroupOverdueNotificationsStoring(),
            toastPresenter: toast,
        )
    }

    @Test
    func `selection is derived from saved events without needing connectivity`() {
        let store = FakeNotificationSettingsStore(settings: NotificationSettings(projectEvents: [
            4: [.taskAssigneeCreated, .taskCommentCreated],
            5: [.taskAssigneeCreated, .taskCommentCreated, .taskCreated],
        ]))
        let viewModel = makeViewModel(store: store)

        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
        #expect(viewModel.projectNotificationPreset(for: otherProject) == .custom)
        #expect(viewModel.projectNotificationPreset(for: Project(id: 6, title: "Empty")) == .disabled)
    }

    @Test
    func `recommended replaces events with assignments and comments and reflects later customization`() async throws {
        let repository = FakeWebhookRepository()
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(repository: repository, store: store)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvents([.taskCreated, .taskReminderFired], for: project)
        await viewModel.setProjectEvents([.taskUpdated], for: otherProject)

        await viewModel.selectProjectNotificationPreset(.recommended, for: project)

        let expected: Set<WebhookEvent> = [.taskAssigneeCreated, .taskCommentCreated]
        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
        #expect(try viewModel.settings.events(for: #require(project.id.remoteValue)) == expected)
        #expect(try store.savedSettings.last?.events(for: #require(project.id.remoteValue)) == expected)
        #expect(try Set(#require(repository.projectWebhooks[4]?.first).events) == expected)
        #expect(try viewModel.settings.events(for: #require(otherProject.id.remoteValue)) == [.taskUpdated])

        await viewModel.setProjectEvent(.taskCreated, isEnabled: true, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
        await viewModel.setProjectEvent(.taskCreated, isEnabled: false, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
    }

    @Test
    func `disabled removes only this device's project webhook`() async throws {
        let external = try Webhook(
            id: 10, targetURL: #require(URL(string: "https://example.com/integration")),
            events: [.taskCreated], projectID: 4,
        )
        let repository = FakeWebhookRepository(projectWebhooks: [4: [external]])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.selectProjectNotificationPreset(.recommended, for: project)
        await viewModel.selectProjectNotificationPreset(.recommended, for: otherProject)

        await viewModel.selectProjectNotificationPreset(.disabled, for: project)

        #expect(viewModel.projectNotificationPreset(for: project) == .disabled)
        #expect(repository.projectWebhooks[4]?.map(\.id) == [external.id])
        #expect(viewModel.projectNotificationPreset(for: otherProject) == .recommended)
        #expect(repository.projectWebhooks[5]?.count == 1)
        #expect(repository.deletedProjectWebhookIDs.map(\.projectID) == [4])
    }

    @Test(
        arguments: [ProjectNotificationPreset.disabled, .recommended],
        [VikunjaError.offline, .server(message: "Configuration changed", statusCode: 409)],
    )
    func `failed preset changes preserve selection and can be retried`(
        _ preset: ProjectNotificationPreset, error: VikunjaError,
    ) async {
        let repository = FakeWebhookRepository()
        let store = FakeNotificationSettingsStore()
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(repository: repository, store: store, toast: toast)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvents([.taskCreated], for: project)
        let previousSettings = viewModel.settings
        let previousSaveCount = store.savedSettings.count
        repository.mutationError = error

        await viewModel.selectProjectNotificationPreset(preset, for: project)

        #expect(viewModel.settings == previousSettings)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
        #expect(store.savedSettings.count == previousSaveCount)
        #expect(toast.shownMessages.last?.style == .error)
        #expect(viewModel.pendingChange == nil)

        repository.mutationError = nil
        await viewModel.selectProjectNotificationPreset(preset, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == preset)
    }

    @Test
    func `enabled settings without a registration cannot claim a preset was saved`() async {
        let store = FakeNotificationSettingsStore(settings: NotificationSettings(isEnabled: true))
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(store: store, toast: toast)

        await viewModel.selectProjectNotificationPreset(.recommended, for: project)

        #expect(viewModel.projectNotificationPreset(for: project) == .disabled)
        #expect(store.savedSettings.isEmpty)
        #expect(toast.shownMessages.last?.style == .error)
    }

    @Test
    func `customize does not overwrite existing events`() async {
        let store = FakeNotificationSettingsStore(settings: NotificationSettings(projectEvents: [4: [.taskCreated]]))
        let viewModel = makeViewModel(store: store)
        await viewModel.selectProjectNotificationPreset(.custom, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
        #expect(store.savedSettings.isEmpty)
    }

    @Test
    func `a second preset intent cannot interrupt an in flight save`() async {
        let repository = FakeWebhookRepository()
        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.confirmEnable()
        repository.onFetchWebhooks = {
            #expect(viewModel.pendingChange == .project(4))
            await viewModel.selectProjectNotificationPreset(.disabled, for: project)
            #expect(viewModel.pendingChange == .project(4))
        }

        await viewModel.selectProjectNotificationPreset(.recommended, for: project)

        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
        #expect(viewModel.pendingChange == nil)
    }

    @Test
    func `cancelled saves leave the stored selection and do not show an error`() async {
        let repository = FakeWebhookRepository()
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(repository: repository, toast: toast)
        await viewModel.load()
        await viewModel.confirmEnable()
        let previousSettings = viewModel.settings
        repository.mutationError = CancellationError()

        await viewModel.selectProjectNotificationPreset(.recommended, for: project)

        #expect(viewModel.settings == previousSettings)
        #expect(viewModel.pendingChange == nil)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test
    func `details exclude our webhook and retain cached data across offline failures`() async throws {
        let external = try Webhook(
            id: 10, targetURL: #require(URL(string: "https://example.com/integration")),
            events: [.taskCreated], projectID: 4,
        )
        let repository = FakeWebhookRepository(projectWebhooks: [4: [external]])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.selectProjectNotificationPreset(.recommended, for: project)
        #expect(viewModel.hasWebhookSigningSecret)

        await viewModel.loadOtherWebhooks(for: project)
        #expect(viewModel.otherWebhookLoadState(for: project).value?.map(\.id) == [10])
        repository.fetchError = VikunjaError.offline
        await viewModel.loadOtherWebhooks(for: project)
        #expect(viewModel.otherWebhookLoadState(for: project).failureMessage != nil)
        #expect(viewModel.cachedOtherWebhooks(for: project).map(\.id) == [10])
        #expect(viewModel.otherWebhookLoadState(for: otherProject) == .idle)

        repository.fetchError = nil
        await viewModel.loadOtherWebhooks(for: project)
        #expect(viewModel.otherWebhookLoadState(for: project).isLoaded)
    }

    @Test
    func `details failures are distinguishable from an empty list and cancellation can retry`() async {
        let repository = FakeWebhookRepository()
        let viewModel = makeViewModel(repository: repository)
        repository.fetchError = VikunjaError.offline
        await viewModel.loadOtherWebhooks(for: project)
        #expect(viewModel.otherWebhookLoadState(for: project).failureMessage != nil)
        #expect(!viewModel.otherWebhookLoadState(for: project).isLoaded)
        #expect(!viewModel.hasWebhookSigningSecret)

        repository.fetchError = CancellationError()
        await viewModel.loadOtherWebhooks(for: project)
        #expect(viewModel.otherWebhookLoadState(for: project) == .idle)

        repository.fetchError = nil
        await viewModel.loadOtherWebhooks(for: project)
        #expect(viewModel.otherWebhookLoadState(for: project).value?.isEmpty == true)
    }
}
