import Foundation
import VikunjaCore

/// On-device cache of each account's last known per-project task-completion
/// tallies, shown instantly on the Projects list before each project's own
/// count request resolves. Stores one JSON-encoded dictionary per account
/// (keyed by project id) rather than one value per key, since there's a
/// whole dictionary to cache instead of a single scalar like
/// `ServerVersionStore`'s. Keyed by account id, so switching instances picks
/// up that instance's own tallies.
struct ProjectTaskSummaryStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: UUID) -> String {
        "cachedProjectTaskSummaries.\(accountID.uuidString)"
    }

    func cachedTaskSummaries(forAccountID accountID: UUID) -> [Int: CachedProjectTaskSummary] {
        guard let data = defaults.data(forKey: key(for: accountID)) else { return [:] }
        return (try? JSONDecoder().decode([Int: CachedProjectTaskSummary].self, from: data)) ?? [:]
    }

    func setCachedTaskSummaries(_ summaries: [Int: CachedProjectTaskSummary], forAccountID accountID: UUID) {
        guard let data = try? JSONEncoder().encode(summaries) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }
}

/// Binds `ProjectTaskSummaryStore` to one account, so `ProjectsListViewModel`
/// (which only knows `VikunjaCore`'s `ProjectTaskSummaryCaching` protocol)
/// never needs an account id of its own.
struct AccountProjectTaskSummaryCache: ProjectTaskSummaryCaching {
    let store: ProjectTaskSummaryStore
    let accountID: UUID

    func cachedTaskSummaries() -> [Int: CachedProjectTaskSummary] {
        store.cachedTaskSummaries(forAccountID: accountID)
    }

    func setCachedTaskSummaries(_ summaries: [Int: CachedProjectTaskSummary]) {
        store.setCachedTaskSummaries(summaries, forAccountID: accountID)
    }
}
