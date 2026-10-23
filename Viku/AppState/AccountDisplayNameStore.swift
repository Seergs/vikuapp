import Foundation
import VikunjaCore

/// On-device cache of each account's display name (`User.name`, falling back
/// to `User.username`), backing the avatar initials shown on the Settings
/// landing screen. Mirrors `AccountTimezoneStore`: lets
/// `DefaultProjectSettingsViewModel` show the last known name instantly,
/// before its own `load()` resolves, and rewrites it once that confirms the
/// current one. Keyed by account id, so switching instances picks up that
/// instance's own name.
struct AccountDisplayNameStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: UUID) -> String {
        "cachedAccountDisplayName.\(accountID.uuidString)"
    }

    func cachedDisplayName(forAccountID accountID: UUID) -> String? {
        defaults.string(forKey: key(for: accountID))
    }

    func setCachedDisplayName(_ name: String?, forAccountID accountID: UUID) {
        if let name {
            defaults.set(name, forKey: key(for: accountID))
        } else {
            defaults.removeObject(forKey: key(for: accountID))
        }
    }
}

/// Binds `AccountDisplayNameStore` to one account, so
/// `DefaultProjectSettingsViewModel` (which only knows `VikunjaCore`'s
/// `AccountDisplayNameCaching` protocol) never needs an account id of its own.
struct AccountDisplayNameCache: AccountDisplayNameCaching {
    let store: AccountDisplayNameStore
    let accountID: UUID

    func cachedDisplayName() -> String? {
        store.cachedDisplayName(forAccountID: accountID)
    }

    func setCachedDisplayName(_ name: String?) {
        store.setCachedDisplayName(name, forAccountID: accountID)
    }
}
