/// Whether the user wants Viku's Home Screen icon to show a count of
/// overdue-plus-due-today tasks, without the view knowing where that
/// preference is persisted. Implemented by the app target's
/// `AppIconBadgeCenter` and injected via `AppContainer`, the same way
/// `AppThemeStoring` is. Turning this off is also where the icon's badge
/// actually gets cleared — see the concrete type's `setEnabled(_:)`.
@MainActor
public protocol AppIconBadgeStoring: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}
