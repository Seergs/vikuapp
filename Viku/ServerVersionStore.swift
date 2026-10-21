import Foundation
import VikunjaCore

/// On-device cache of each account's last known Vikunja server version
/// (`VikunjaServerInfo.version`). A plain preference, not a credential, so
/// `UserDefaults` is the right home. Keyed by account id, so removing an
/// instance only drops that instance's entry. Mirrors
/// `DefaultProjectStore`/`AccountTimezoneStore`'s shape, but conforms
/// directly to `ServerVersionCaching` since `ConnectionsListViewModel` reads
/// several accounts at once rather than one bound to a single id.
struct ServerVersionStore: ServerVersionCaching {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: UUID) -> String {
        "cachedServerVersion.\(accountID.uuidString)"
    }

    func cachedVersion(forAccountID accountID: UUID) -> String? {
        defaults.string(forKey: key(for: accountID))
    }

    func setCachedVersion(_ version: String?, forAccountID accountID: UUID) {
        if let version {
            defaults.set(version, forKey: key(for: accountID))
        } else {
            defaults.removeObject(forKey: key(for: accountID))
        }
    }
}
