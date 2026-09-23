import Observation
import VikunjaCore
import VikunjaNetworking

/// Session-only dev-tools state, owned by `AppContainer`. Deliberately holds
/// no `UserDefaults`/Keychain-backed state: it exists to be a quick,
/// throwaway toggle, not a persisted preference, so it resets to its default
/// every launch. Only ever read/written when `BuildConfig.isDevBuild` is
/// true, but harmless to construct otherwise.
@MainActor
@Observable
final class DevToolsCenter: DevBadgeVisibilityStoring, NetworkRequestLoggingStoring {
    var isDevBadgeVisible = true

    func setDevBadgeVisible(_ visible: Bool) {
        isDevBadgeVisible = visible
    }

    /// Bridges to `VikunjaNetworking`'s actual switch (`URLSessionAPIClient`
    /// checks that directly), so this type just forwards to it rather than
    /// holding a second, easy-to-desync copy of the same bool.
    var isNetworkRequestLoggingEnabled: Bool {
        NetworkRequestLogging.shared.isEnabled
    }

    func setNetworkRequestLoggingEnabled(_ enabled: Bool) {
        NetworkRequestLogging.shared.isEnabled = enabled
    }
}
