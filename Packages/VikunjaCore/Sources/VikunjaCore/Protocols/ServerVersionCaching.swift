import Foundation

/// What `ConnectionsListViewModel` needs in order to show each account's
/// last known Vikunja server version instantly on the Connections screen,
/// before that account's own `/info` probe resolves, without knowing
/// anything about `UserDefaults`. Implemented by `ServerVersionStore` in the
/// app target and injected via `AppContainer`.
///
/// No expiry: the last successful probe's value is shown until a newer one
/// replaces it, the same "last known good value, refreshed in background"
/// shape as `DefaultProjectCaching`/`AccountTimezoneCaching`.
@MainActor
public protocol ServerVersionCaching {
    func cachedVersion(forAccountID accountID: InstanceAccount.ID) -> String?
    func setCachedVersion(_ version: String?, forAccountID accountID: InstanceAccount.ID)
}
