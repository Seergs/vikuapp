/// The OS authorization a `Features/*` view model needs to turn the app
/// icon badge on, without importing `UserNotifications` or knowing that the
/// same authorization is shared with push notifications (iOS exposes one
/// combined `.alert`/`.sound`/`.badge` permission, not a separate one per
/// capability). Implemented by the app target's `APNsPermissionCenter` and
/// injected via `AppContainer`.
@MainActor
public protocol AppIconBadgePermissionRequesting: AnyObject {
    /// Prompts the user if the OS hasn't recorded a decision yet; otherwise
    /// returns the existing decision with no prompt. `false` means denied
    /// (or previously denied) — the caller must not treat this as a
    /// transient failure to retry, only as "point the user at the system
    /// Settings app instead."
    func requestAuthorization() async -> Bool

    /// The current OS authorization status, without prompting — lets a
    /// screen show the "denied" banner as soon as it appears, before the
    /// user even touches the toggle (e.g. they revoked it from the system
    /// Settings app since the last launch).
    func isAuthorizationDenied() async -> Bool
}
