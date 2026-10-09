import Foundation
import VikunjaCore

/// On-device cache of each account's Vikunja default project
/// (`settings.default_project_id` from `GET /api/v1/user`). It's a plain
/// preference, not a credential, so `UserDefaults` is the right home — the
/// Keychain rule is for secrets only.
///
/// Two things are cached here, independently:
/// - the bare project id (`projectID`/`setProjectID`), refreshed once per app
///   launch and on account switch by `AppContainer.refreshDefaultProject` —
///   the server-side source of truth for "what the default project is";
/// - a display snapshot (`cachedProject`/`setCachedProject`: id + title +
///   hex color) that `QuickAddTaskViewModel` reads through
///   `AccountDefaultProjectCache` to show its project field instantly, before
///   its own `load()` resolves, and rewrites once that confirms the real
///   default.
///
/// Keyed by account id, so switching instances picks up that instance's own
/// default.
struct DefaultProjectStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func idKey(for accountID: UUID) -> String {
        "defaultProjectID.\(accountID.uuidString)"
    }

    private func cacheKey(for accountID: UUID) -> String {
        "cachedDefaultProject.\(accountID.uuidString)"
    }

    /// The cached default project id for the account, or `nil` if none is
    /// stored (or the stored value is Vikunja's "unset" sentinel, `0`).
    func projectID(forAccountID accountID: UUID) -> Int? {
        let stored = defaults.integer(forKey: idKey(for: accountID))
        return stored == 0 ? nil : stored
    }

    func setProjectID(_ projectID: Int?, forAccountID accountID: UUID) {
        if let projectID, projectID != 0 {
            defaults.set(projectID, forKey: idKey(for: accountID))
        } else {
            defaults.removeObject(forKey: idKey(for: accountID))
        }
    }

    func cachedProject(forAccountID accountID: UUID) -> CachedDefaultProject? {
        guard let data = defaults.data(forKey: cacheKey(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(CachedDefaultProject.self, from: data)
    }

    func setCachedProject(_ project: CachedDefaultProject?, forAccountID accountID: UUID) {
        if let project, let data = try? JSONEncoder().encode(project) {
            defaults.set(data, forKey: cacheKey(for: accountID))
        } else {
            defaults.removeObject(forKey: cacheKey(for: accountID))
        }
    }
}

/// Binds `DefaultProjectStore`'s display cache to one account, so
/// `QuickAddTaskViewModel` (which only knows `VikunjaCore`'s
/// `DefaultProjectCaching` protocol) never needs an account id of its own.
struct AccountDefaultProjectCache: DefaultProjectCaching {
    let store: DefaultProjectStore
    let accountID: UUID

    func cachedDefaultProject() -> CachedDefaultProject? {
        store.cachedProject(forAccountID: accountID)
    }

    func setCachedDefaultProject(_ project: CachedDefaultProject?) {
        store.setCachedProject(project, forAccountID: accountID)
    }
}
