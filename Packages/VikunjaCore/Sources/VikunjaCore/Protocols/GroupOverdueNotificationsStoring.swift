/// Whether overdue-task push notifications should arrive as one combined
/// push per day instead of one per overdue task, without the view knowing
/// where that preference is persisted. Implemented by the app target's
/// `GroupOverdueNotificationsStore` and injected via `AppContainer`, the same
/// way `AppThemeStoring` is.
///
/// Unlike `NotificationSettingsStore`, this is device-wide, not scoped per
/// `InstanceAccount.ID`: it controls how the relay (`viku-apn-relay`) renders
/// the push, not which Vikunja webhooks exist, so there's nothing
/// account-specific about it. `NotificationsViewModel` is the one place that
/// both reads this (to show the toggle) and fans a change out to every
/// account that currently has push enabled.
@MainActor
public protocol GroupOverdueNotificationsStoring: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}
