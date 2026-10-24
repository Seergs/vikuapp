import Observation
import VikunjaCore

/// Drives the device-wide "Group Overdue Notifications" toggle on the
/// Settings landing screen's "General" section. Unlike `NotificationsView`'s
/// other toggles, this one is not scoped to any single `InstanceAccount` —
/// see `GroupOverdueNotificationsStoring`'s doc comment for why — so
/// `setEnabled(_:)` fans a change out to every account on this device that
/// currently has push enabled, mirroring
/// `AppContainer.syncNotificationWebhooksForAllAccounts()`'s own per-account
/// loop: each account's `updatePreferences` call is independent, so one
/// account's failure (silently ignored, like every other relay call in this
/// app) never stops another's from going through.
@MainActor
@Observable
public final class GroupOverdueNotificationsViewModel {
    public private(set) var isEnabled: Bool

    private let store: GroupOverdueNotificationsStoring
    private let accountStore: AccountStoreProtocol
    private let notificationSettingsStore: NotificationSettingsStore
    private let pushNotificationRegistering: PushNotificationRegistering

    public init(
        store: GroupOverdueNotificationsStoring,
        accountStore: AccountStoreProtocol,
        notificationSettingsStore: NotificationSettingsStore,
        pushNotificationRegistering: PushNotificationRegistering,
    ) {
        self.store = store
        self.accountStore = accountStore
        self.notificationSettingsStore = notificationSettingsStore
        self.pushNotificationRegistering = pushNotificationRegistering
        self.isEnabled = store.isEnabled
    }

    public func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        store.setEnabled(enabled)

        guard let accounts = try? await accountStore.fetchAccounts() else { return }
        for account in accounts where notificationSettingsStore.settings(for: account.id).isEnabled {
            try? await pushNotificationRegistering.updatePreferences(
                groupOverdueNotifications: enabled,
                accountID: account.id,
            )
        }
    }
}
