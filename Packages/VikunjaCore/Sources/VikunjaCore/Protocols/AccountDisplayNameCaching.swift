import Foundation

/// What `DefaultProjectSettingsViewModel` needs in order to show the
/// account's last known display name (and therefore its avatar initials)
/// immediately on the Settings screen, before its own `load()` resolves,
/// instead of the "?" placeholder, without knowing anything about
/// `UserDefaults`. Implemented by `AccountDisplayNameCache` in the app target
/// and injected via `AppContainer`.
///
/// No expiry: the last known value is shown until `load()` reports a fresh
/// one, the same "last known good value, refreshed in background" shape as
/// `AccountTimezoneCaching`/`ServerVersionCaching`.
@MainActor
public protocol AccountDisplayNameCaching {
    func cachedDisplayName() -> String?
    func setCachedDisplayName(_ name: String?)
}
