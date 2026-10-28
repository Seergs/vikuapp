import Foundation
import VikunjaCore

/// On-device cache of each account's signed-in Vikunja user, keyed by
/// account id. Comments need an author name for a comment created while
/// offline, before the server has ever seen it — this is the one place that
/// identity is available without a network round trip. Updated whenever
/// `AppContainer` already fetches the current user, so it never adds a
/// request of its own.
struct CurrentUserStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: InstanceAccount.ID) -> String {
        "cachedCurrentUser.\(accountID.uuidString)"
    }

    func user(for accountID: InstanceAccount.ID) -> User? {
        guard let data = defaults.data(forKey: key(for: accountID)) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedUser.self, from: data) else { return nil }
        return cached.user
    }

    func setUser(_ user: User?, for accountID: InstanceAccount.ID) {
        guard let user else {
            defaults.removeObject(forKey: key(for: accountID))
            return
        }
        guard let data = try? JSONEncoder().encode(CachedUser(user: user)) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    private struct CachedUser: Codable {
        let id: Int
        let username: String
        let name: String?
        let email: String?

        init(user: User) {
            self.id = user.id
            self.username = user.username
            self.name = user.name
            self.email = user.email
        }

        var user: User {
            User(id: id, username: username, name: name, email: email)
        }
    }
}
