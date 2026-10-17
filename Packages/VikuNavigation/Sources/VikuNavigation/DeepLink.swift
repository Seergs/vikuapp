import Observation

/// An external entry point resolved into an in-app destination: quick-add —
/// reached from the Today widget's "add" button, a `viku://quick-add` URL
/// (Shortcuts, other apps), the Siri shortcut, or a Control Center control —
/// or a tapped push notification resolving to a task. A `today` link will be
/// added here once its in-app routing exists.
///
/// URL parsing lives in the app target (`DeepLink.init?(url:)`), since the
/// `viku` scheme string is defined in `VikuWidgetKit`; this enum stays
/// dependency-free so `VikuWidgetKit`'s App Intents can build one directly.
/// The push parser (`init?(pushUserInfo:)`) lives in this file instead,
/// since it has no such dependency.
public enum DeepLink: Equatable, Sendable {
    /// Present the tab-bar quick-add sheet, defaulting to the given project
    /// when supplied.
    case quickAdd(projectID: Int?)
    /// Open a task's detail screen. `accountKey` is the `InstanceAccount.id`
    /// the relay's push payload carries (see `viku-apn-relay`'s
    /// `account_key`) — the consumer resolves `id` against that account's
    /// repositories, never the currently active one blindly, since the two
    /// can differ.
    case task(id: Int, accountKey: String)
}

public extension DeepLink {
    /// Parses a push notification's `userInfo` into a `.task` deep link.
    /// `nil` for any payload missing the fields `MainTabView` needs to
    /// resolve and open the task — an event with no task (e.g. a
    /// project-level event), or a malformed/foreign payload. The relay is an
    /// external service, so this treats its payload as untrusted input
    /// rather than assuming the shape it currently sends.
    init?(pushUserInfo userInfo: [AnyHashable: Any]) {
        guard let taskID = userInfo["task_id"] as? Int,
              let accountKey = userInfo["account_key"] as? String, !accountKey.isEmpty
        else { return nil }
        self = .task(id: taskID, accountKey: accountKey)
    }
}

/// Holds the deep link the app was last opened with until a screen is mounted
/// and ready to act on it: set from `RootView`'s `.onOpenURL` or an App
/// Intent's `perform()`, consumed by `QuickAddOverlay`. Not view `@State`, so a
/// link that arrives during a cold launch — before the tab shell exists —
/// survives until the shell is up.
///
/// A process-wide singleton (`shared`) rather than a `@Dependency`:
/// `OpenQuickAddIntent` sets `openAppWhenRun`, so its `perform()` runs in the
/// app's process and touches the same instance the UI observes, with no
/// registration-timing window to lose an invocation in.
@Observable
@MainActor
public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    public private(set) var pending: DeepLink?

    public init() {}

    public func open(_ link: DeepLink) {
        pending = link
    }

    /// Clears `pending` once a screen has acted on it, so it doesn't re-fire
    /// the next time that screen appears.
    public func clear() {
        pending = nil
    }
}
