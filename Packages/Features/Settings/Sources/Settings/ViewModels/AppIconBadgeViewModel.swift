import Observation
import VikunjaCore

/// Drives the "App Icon Badge" row on the Settings landing screen: the
/// toggle itself (gated behind a consent sheet on first enable — see
/// `AppIconBadgeConsentSheet`) and the "denied" banner when the OS
/// permission isn't granted. Mirrors `NotificationsViewModel`'s
/// enable/denied shape, scaled down — there's no server-side sync here, just
/// a local preference plus the OS permission it depends on.
@MainActor
@Observable
public final class AppIconBadgeViewModel {
    public private(set) var isEnabled: Bool
    /// Set when the OS permission is (or has become) denied — the view
    /// shows a banner pointing at the system Settings app instead of
    /// letting the toggle take effect.
    public private(set) var isPermissionDenied = false
    public private(set) var isRequestingPermission = false

    private let store: AppIconBadgeStoring
    private let permissionRequester: AppIconBadgePermissionRequesting

    public init(store: AppIconBadgeStoring, permissionRequester: AppIconBadgePermissionRequesting) {
        self.store = store
        self.permissionRequester = permissionRequester
        self.isEnabled = store.isEnabled
    }

    /// Re-checks the OS permission while the feature is on — catches the
    /// user having revoked it from the system Settings app since the last
    /// launch. Call on the screen's appearance, mirroring
    /// `NotificationsViewModel.load()`.
    public func refreshPermissionStatus() async {
        guard isEnabled else { return }
        isPermissionDenied = await permissionRequester.isAuthorizationDenied()
    }

    /// Called from the consent sheet's confirm button — this is what
    /// actually triggers the OS permission prompt.
    public func confirmEnable() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        guard await permissionRequester.requestAuthorization() else {
            isPermissionDenied = true
            return
        }
        isPermissionDenied = false
        isEnabled = true
        store.setEnabled(true)
    }

    public func disable() {
        isEnabled = false
        isPermissionDenied = false
        store.setEnabled(false)
    }
}
