import VikunjaCore

/// Destinations pushable within the Settings tab's own navigation stack.
public enum SettingsRoute: Hashable, Sendable {
    /// The list of saved instance connections.
    case connections
    /// The add/edit form for a single connection.
    case connectionForm(ConnectionFormMode)
    /// The account-wide label management screen.
    case manageLabels
    /// The push-notification opt-in, user-level toggle, and per-project list.
    case notifications
    /// One project's own webhook event selection, reached from
    /// `.notifications`. Carries the project itself (feature-private
    /// payload) rather than just its id, so the destination doesn't need a
    /// repository round trip to show its title/color.
    case projectNotifications(Project)
    /// App version/build, external links, privacy note, and licensing.
    case about
}
