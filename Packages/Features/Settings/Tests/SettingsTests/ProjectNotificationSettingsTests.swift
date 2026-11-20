import Foundation
@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct ProjectNotificationSettingsTests {
    private let project = Project(id: 4, title: "Work")
    private let otherProject = Project(id: 5, title: "Home")

    private func makeViewModel(
        accountID: InstanceAccount.ID = fakeAccountID,
        repository: FakeWebhookRepository = FakeWebhookRepository(),
        store: FakeNotificationSettingsStore = FakeNotificationSettingsStore(),
        toast: FakeToastPresenter = FakeToastPresenter(),
        registering: FakePushNotificationRegistering = FakePushNotificationRegistering(),
    ) -> NotificationsViewModel {
        NotificationsViewModel(
            accountID: accountID,
            webhookRepository: repository,
            projectRepository: FakeProjectRepository(projects: [project, otherProject]),
            userRepository: FakeUserRepository(),
            pushNotificationRegistering: registering,
            notificationSettingsStore: store,
            groupOverdueNotificationsStore: FakeGroupOverdueNotificationsStoring(),
            toastPresenter: toast,
        )
    }

    @Test
    func `selection is derived from saved events without needing connectivity`() {
        let store = FakeNotificationSettingsStore(settings: NotificationSettings(projectEvents: [
            4: [.taskAssigneeCreated],
            5: [.taskAssigneeCreated, .taskCommentCreated, .taskCreated],
        ], projectAssignmentModes: [4: .onlyMe]))
        let viewModel = makeViewModel(store: store)

        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
        #expect(viewModel.projectNotificationPreset(for: otherProject) == .custom)
        #expect(viewModel.projectNotificationPreset(for: Project(id: 6, title: "Empty")) == .disabled)
    }

    @Test
    func `recommended enables only personal assignments and reflects later customization`() async throws {
        let repository = FakeWebhookRepository()
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(repository: repository, store: store)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvents([.taskCreated, .taskReminderFired, .taskCommentCreated], for: project)
        await viewModel.setProjectEvents([.taskUpdated], for: otherProject)

        await viewModel.selectProjectNotificationPreset(.recommended, for: project)

        let expected: Set<WebhookEvent> = [.taskAssigneeCreated]
        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
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

        #expect(viewModel.settings.projectEvents == previousSettings.projectEvents)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
        if preset == .recommended {
            #expect(viewModel.settings.assignmentMode(for: 4) == .onlyMe)
            #expect(store.settings(for: fakeAccountID).assignmentMode(for: 4) == .onlyMe)
        } else {
            #expect(store.savedSettings.count == previousSaveCount)
        }
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

        #expect(viewModel.settings.projectEvents == previousSettings.projectEvents)
        #expect(viewModel.settings.assignmentMode(for: 4) == .onlyMe)
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

    @Test
    func `legacy assignments display all and disabled projects keep their saved filter`() {
        let store = FakeNotificationSettingsStore(settings: NotificationSettings(
            projectEvents: [4: [.taskAssigneeCreated]], projectAssignmentModes: [5: .onlyMe],
        ))
        let viewModel = makeViewModel(store: store)
        #expect(viewModel.assignmentSelection(for: project) == .all)
        #expect(viewModel.assignmentSelection(for: otherProject) == .disabled)
    }

    @Test
    func `assignment choices persist per project and changing filters does not recreate webhooks`() async throws {
        let registering = FakePushNotificationRegistering()
        let repository = FakeWebhookRepository()
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(repository: repository, store: store, registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.setProjectEvent(.taskCommentCreated, isEnabled: true, for: project)
        await viewModel.selectAssignments(.onlyMe, for: project)
        let webhook = try #require(repository.projectWebhooks[4]?.first)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
        #expect(Set(webhook.events) == [.taskAssigneeCreated, .taskCommentCreated])
        #expect(registering.updatedProjectPreferences.last?.mode == .onlyMe)
        #expect(registering.updatedProjectPreferences.last?.projectID == 4)
        #expect(registering.updatedProjectPreferences.last?.accountID == fakeAccountID)

        await viewModel.selectAssignments(.all, for: otherProject)
        await viewModel.selectAssignments(.all, for: project)
        #expect(repository.projectWebhooks[4]?.first?.id == webhook.id)
        #expect(registering.updatedProjectPreferences.last?.mode == .all)
        #expect(viewModel.assignmentSelection(for: otherProject) == .all)
        let requestCount = registering.updatedProjectPreferences.count
        await viewModel.selectAssignments(.disabled, for: project)
        #expect(registering.updatedProjectPreferences.count == requestCount)
        #expect(viewModel.settings.events(for: 4) == [.taskCommentCreated])
        #expect(viewModel.assignmentSelection(for: project) == .disabled)
        #expect(viewModel.assignmentSelection(for: otherProject) == .all)
        let reopened = makeViewModel(store: store)
        #expect(reopened.assignmentSelection(for: otherProject) == .all)
    }

    @Test(arguments: [VikunjaError.offline, .server(message: "Conflict", statusCode: 409)])
    func `failed relay updates preserve settings and retry succeeds`(_ error: VikunjaError) async {
        let registering = FakePushNotificationRegistering()
        let repository = FakeWebhookRepository()
        let store = FakeNotificationSettingsStore()
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(repository: repository, store: store, toast: toast, registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        let before = viewModel.settings
        registering.projectPreferencesError = error
        await viewModel.selectAssignments(.onlyMe, for: project)
        #expect(viewModel.settings == before)
        #expect(store.settings(for: fakeAccountID) == before)
        #expect(repository.projectWebhooks[4] == nil)
        #expect(toast.shownMessages.last?.style == .error)
        #expect(viewModel.pendingChange == nil)
        registering.projectPreferencesError = nil
        await viewModel.selectAssignments(.onlyMe, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
        #expect(makeViewModel(store: store).assignmentSelection(for: project) == .onlyMe)
    }

    @Test
    func `failed webhook activation keeps assignments off and retains the confirmed relay filter`() async {
        let registering = FakePushNotificationRegistering()
        let repository = FakeWebhookRepository()
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(repository: repository, store: store, registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        repository.mutationError = VikunjaError.offline
        await viewModel.selectAssignments(.onlyMe, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .disabled)
        #expect(viewModel.settings.assignmentMode(for: 4) == .onlyMe)
        #expect(store.settings(for: fakeAccountID).assignmentMode(for: 4) == .onlyMe)
        repository.mutationError = nil
        await viewModel.selectProjectNotificationPreset(.recommended, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
        #expect(registering.updatedProjectPreferences.last?.mode == .onlyMe)
    }

    @Test
    func `cancelled relay changes restore the selection and allow retry`() async {
        let registering = FakePushNotificationRegistering()
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(toast: toast, registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        registering.projectPreferencesError = CancellationError()
        await viewModel.selectAssignments(.onlyMe, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .disabled)
        #expect(viewModel.pendingChange == nil)
        #expect(toast.shownMessages.isEmpty)
        registering.projectPreferencesError = nil
        await viewModel.selectAssignments(.onlyMe, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
    }

    @Test
    func `relay filter is configured before enabling webhooks and overlapping writes are rejected`() async {
        let registering = FakePushNotificationRegistering()
        let repository = FakeWebhookRepository()
        let viewModel = makeViewModel(repository: repository, registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        registering.onProjectPreferences = { @MainActor in
            #expect(repository.projectWebhooks[4] == nil)
            #expect(viewModel.pendingEvent == .taskAssigneeCreated)
            await viewModel.selectAssignments(.all, for: project)
            await viewModel.selectProjectNotificationPreset(.disabled, for: otherProject)
        }
        await viewModel.selectAssignments(.onlyMe, for: project)
        #expect(registering.updatedProjectPreferences.count == 1)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
    }

    @Test
    func `the same project ID in different connections retains independent modes`() async {
        let store = FakeNotificationSettingsStore()
        let firstID = UUID()
        let secondID = UUID()
        let registering = FakePushNotificationRegistering()
        let first = makeViewModel(accountID: firstID, store: store, registering: registering)
        let second = makeViewModel(accountID: secondID, store: store, registering: registering)
        await first.load()
        await first.confirmEnable()
        await first.selectAssignments(.onlyMe, for: project)
        await second.load()
        await second.confirmEnable()
        await second.selectAssignments(.all, for: project)
        #expect(store.settings(for: firstID).assignmentMode(for: 4) == .onlyMe)
        #expect(store.settings(for: secondID).assignmentMode(for: 4) == .all)
        #expect(makeViewModel(accountID: firstID, store: store).assignmentSelection(for: project) == .onlyMe)
        #expect(makeViewModel(accountID: secondID, store: store).assignmentSelection(for: project) == .all)
    }

    @Test
    func `failed filter changes on an active webhook preserve its previous mode`() async {
        let registering = FakePushNotificationRegistering()
        let store = FakeNotificationSettingsStore()
        let viewModel = makeViewModel(store: store, registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.selectAssignments(.onlyMe, for: project)
        registering.projectPreferencesError = VikunjaError.offline
        await viewModel.selectAssignments(.all, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .onlyMe)
        #expect(makeViewModel(store: store).assignmentSelection(for: project) == .onlyMe)
        registering.projectPreferencesError = nil
        await viewModel.selectAssignments(.all, for: project)
        #expect(viewModel.assignmentSelection(for: project) == .all)
    }

    @Test
    func `recommended changes an all assignments filter to only me without retaining comments`() async {
        let registering = FakePushNotificationRegistering()
        let viewModel = makeViewModel(registering: registering)
        await viewModel.load()
        await viewModel.confirmEnable()
        await viewModel.selectAssignments(.all, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
        await viewModel.selectProjectNotificationPreset(.recommended, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .recommended)
        #expect(registering.updatedProjectPreferences.last?.mode == .onlyMe)
        #expect(viewModel.settings.events(for: 4) == [.taskAssigneeCreated])
        await viewModel.setProjectEvent(.taskCommentCreated, isEnabled: true, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
        await viewModel.selectProjectNotificationPreset(.recommended, for: project)
        #expect(viewModel.settings.events(for: 4) == [.taskAssigneeCreated])
        await viewModel.selectAssignments(.all, for: project)
        #expect(viewModel.projectNotificationPreset(for: project) == .custom)
    }
}
