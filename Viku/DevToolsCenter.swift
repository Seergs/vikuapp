import Observation
import VikunjaCore

/// Session-only dev-tools state, owned by `AppContainer`. Deliberately holds
/// no `UserDefaults`/Keychain-backed state: it exists to be a quick,
/// throwaway toggle, not a persisted preference, so it resets to its default
/// every launch. Only ever read/written when `BuildConfig.isDevBuild` is
/// true, but harmless to construct otherwise.
@MainActor
@Observable
final class DevToolsCenter: DevBadgeVisibilityStoring {
    var isDevBadgeVisible = true

    func setDevBadgeVisible(_ visible: Bool) {
        isDevBadgeVisible = visible
    }
}
