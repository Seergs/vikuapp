import Foundation
import VikunjaCore

/// On-device storage of the project or saved filter pinned as the Home tab's
/// content. Unlike `DefaultProjectStore`, there's no server-side value to
/// reconcile against on load — this store *is* the source of truth for the
/// pin, not just a display cache of one. `nil` means "Today" (no pin).
/// Keyed by account id, so switching instances picks up that instance's own
/// pin.
struct HomeSelectionStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: UUID) -> String {
        "homeSelection.\(accountID.uuidString)"
    }

    func selection(forAccountID accountID: UUID) -> CachedHomeSelection? {
        guard let data = defaults.data(forKey: key(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(CachedHomeSelection.self, from: data)
    }

    func setSelection(_ selection: CachedHomeSelection?, forAccountID accountID: UUID) {
        if let selection, let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: key(for: accountID))
        } else {
            defaults.removeObject(forKey: key(for: accountID))
        }
    }
}

/// Binds `HomeSelectionStore` to one account, so Settings' "Home Screen" row
/// (which only knows `VikunjaCore`'s `HomeSelectionCaching` protocol) never
/// needs an account id of its own.
struct AccountHomeSelectionCache: HomeSelectionCaching {
    let store: HomeSelectionStore
    let accountID: UUID

    func cachedHomeSelection() -> CachedHomeSelection? {
        store.selection(forAccountID: accountID)
    }

    func setCachedHomeSelection(_ selection: CachedHomeSelection?) {
        store.setSelection(selection, forAccountID: accountID)
    }
}
