/// What a view needs in order to read and change whether the "DEV"
/// build-environment badge is shown, without knowing anything about where
/// it's tracked. Deliberately session-only: implementations aren't expected
/// to persist this anywhere, just hold it for the life of the app process.
/// Implemented by the app target's `DevToolsCenter` and injected via
/// `AppContainer`, the same way `AppThemeStoring` is.
@MainActor
public protocol DevBadgeVisibilityStoring: AnyObject {
    var isDevBadgeVisible: Bool { get }
    func setDevBadgeVisible(_ visible: Bool)
}
