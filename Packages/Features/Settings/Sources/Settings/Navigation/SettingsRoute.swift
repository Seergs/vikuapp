import VikunjaCore

/// Destinations pushable within the Settings tab's own navigation stack.
public enum SettingsRoute: Hashable, Sendable {
    /// The appearance/theme picker.
    case appearance
    /// The account-wide Quick Add Magic mode picker and guide.
    case quickAddMagic
    /// The list of saved instance connections.
    case connections
    /// The add/edit form for a single connection.
    case connectionForm(ConnectionFormMode)
    /// The account-wide label management screen.
    case manageLabels
    /// The account's queued offline mutations.
    case pendingSync
    /// The push-notification opt-in, user-level toggle, and per-project list.
    case notifications
    /// One project's notification settings landing screen. Carries the
    /// project so its title is available without a repository round trip.
    case projectNotifications(Project)
    /// Custom webhook event selection, reached through "Customize" on
    /// the project's notification settings landing screen.
    case projectNotificationEvents(Project)
    /// App version/build, external links, privacy note, and licensing.
    case about
}
