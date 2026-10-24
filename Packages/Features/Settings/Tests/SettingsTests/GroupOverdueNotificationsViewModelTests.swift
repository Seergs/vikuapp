import Foundation
@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct GroupOverdueNotificationsViewModelTests {
    private func makeViewModel(
        store: FakeGroupOverdueNotificationsStoring = FakeGroupOverdueNotificationsStoring(),
        accountStore: FakeAccountStore = FakeAccountStore(),
        notificationSettingsStore: FakeNotificationSettingsStore = FakeNotificationSettingsStore(),
        pushNotificationRegistering: FakePushNotificationRegistering = FakePushNotificationRegistering(),
    ) -> GroupOverdueNotificationsViewModel {
        GroupOverdueNotificationsViewModel(
            store: store,
            accountStore: accountStore,
            notificationSettingsStore: notificationSettingsStore,
            pushNotificationRegistering: pushNotificationRegistering,
        )
    }

    @Test
    func `isEnabled starts from the device wide store`() {
        let store = FakeGroupOverdueNotificationsStoring(isEnabled: true)
        let viewModel = makeViewModel(store: store)

        #expect(viewModel.isEnabled)
    }

    @Test
    func `setting the device wide toggle persists it and fans it out to every account with push enabled`() async throws {
        let enabledAccountA = UUID()
        let enabledAccountB = UUID()
        let disabledAccountC = UUID()
        let accountStore = FakeAccountStore()
        try await accountStore.addAccount(
            InstanceAccount(id: enabledAccountA, displayName: "A", baseURL: #require(URL(string: "https://a.example.com"))),
            token: "token-a",
        )
        try await accountStore.addAccount(
            InstanceAccount(id: enabledAccountB, displayName: "B", baseURL: #require(URL(string: "https://b.example.com"))),
            token: "token-b",
        )
        try await accountStore.addAccount(
            InstanceAccount(id: disabledAccountC, displayName: "C", baseURL: #require(URL(string: "https://c.example.com"))),
            token: "token-c",
        )
        let settingsStore = FakeNotificationSettingsStore(settings: NotificationSettings(), accountID: enabledAccountA)
        settingsStore.save(NotificationSettings(isEnabled: true), for: enabledAccountA)
        settingsStore.save(NotificationSettings(isEnabled: true), for: enabledAccountB)
        settingsStore.save(NotificationSettings(isEnabled: false), for: disabledAccountC)
        let store = FakeGroupOverdueNotificationsStoring()
        let registering = FakePushNotificationRegistering()
        let viewModel = makeViewModel(
            store: store,
            accountStore: accountStore,
            notificationSettingsStore: settingsStore,
            pushNotificationRegistering: registering,
        )

        await viewModel.setEnabled(true)

        #expect(viewModel.isEnabled)
        #expect(store.setEnabledCalls == [true])
        // enabledAccountA and enabledAccountB both have push enabled;
        // disabledAccountC must be skipped.
        let updatedAccountIDs = Set(registering.updatedPreferences.map(\.accountID))
        #expect(updatedAccountIDs == [enabledAccountA, enabledAccountB])
        #expect(Set(registering.updatedPreferences.map(\.groupOverdueNotifications)) == [true])
    }

    @Test
    func `a failed relay update for one account does not stop the others from being updated`() async throws {
        let accountA = UUID()
        let accountB = UUID()
        let accountStore = FakeAccountStore()
        try await accountStore.addAccount(
            InstanceAccount(id: accountA, displayName: "A", baseURL: #require(URL(string: "https://a.example.com"))),
            token: "token-a",
        )
        try await accountStore.addAccount(
            InstanceAccount(id: accountB, displayName: "B", baseURL: #require(URL(string: "https://b.example.com"))),
            token: "token-b",
        )
        let settingsStore = FakeNotificationSettingsStore(
            settings: NotificationSettings(isEnabled: true),
            accountID: accountA,
        )
        settingsStore.save(NotificationSettings(isEnabled: true), for: accountB)
        let registering = FakePushNotificationRegistering()
        // accountA fails; accountB must still go through right after it.
        registering.updatePreferencesFailingAccountID = accountA
        let viewModel = makeViewModel(
            accountStore: accountStore,
            notificationSettingsStore: settingsStore,
            pushNotificationRegistering: registering,
        )

        await viewModel.setEnabled(true)

        #expect(registering.updatedPreferences.map(\.accountID) == [accountB])
    }

    @Test
    func `accounts with push disabled are never touched`() async throws {
        let disabledAccount = UUID()
        let accountStore = FakeAccountStore()
        try await accountStore.addAccount(
            InstanceAccount(id: disabledAccount, displayName: "A", baseURL: #require(URL(string: "https://a.example.com"))),
            token: "token-a",
        )
        let settingsStore = FakeNotificationSettingsStore(
            settings: NotificationSettings(isEnabled: false),
            accountID: disabledAccount,
        )
        let registering = FakePushNotificationRegistering()
        let viewModel = makeViewModel(
            accountStore: accountStore,
            notificationSettingsStore: settingsStore,
            pushNotificationRegistering: registering,
        )

        await viewModel.setEnabled(true)

        #expect(registering.updatedPreferences.isEmpty)
    }
}
