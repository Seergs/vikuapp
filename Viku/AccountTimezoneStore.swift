import Foundation
import VikunjaCore

/// On-device cache of each account's Vikunja time zone (`User.timezone`),
/// shown read-only on the Settings landing screen. Mirrors
/// `DefaultProjectStore`'s display cache: lets `DefaultProjectSettingsViewModel`
/// show the last known time zone instantly, before its own `load()` resolves,
/// and rewrites it once that confirms the current one. Keyed by account id,
/// so switching instances picks up that instance's own time zone.
struct AccountTimezoneStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: UUID) -> String {
        "cachedAccountTimezone.\(accountID.uuidString)"
    }

    func cachedTimezone(forAccountID accountID: UUID) -> String? {
        defaults.string(forKey: key(for: accountID))
    }

    func setCachedTimezone(_ timezone: String?, forAccountID accountID: UUID) {
        if let timezone {
            defaults.set(timezone, forKey: key(for: accountID))
        } else {
            defaults.removeObject(forKey: key(for: accountID))
        }
    }
}

/// Binds `AccountTimezoneStore` to one account, so `DefaultProjectSettingsViewModel`
/// (which only knows `VikunjaCore`'s `AccountTimezoneCaching` protocol) never
/// needs an account id of its own.
struct AccountTimezoneCache: AccountTimezoneCaching {
    let store: AccountTimezoneStore
    let accountID: UUID

    func cachedTimezone() -> String? {
        store.cachedTimezone(forAccountID: accountID)
    }

    func setCachedTimezone(_ timezone: String?) {
        store.setCachedTimezone(timezone, forAccountID: accountID)
    }
}
