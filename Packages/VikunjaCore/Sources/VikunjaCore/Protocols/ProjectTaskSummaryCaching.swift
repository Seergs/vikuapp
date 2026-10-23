import Foundation

/// A project's cached task-completion tally (`done` of `total`), just enough
/// for `ProjectsListViewModel` to show a project's last known progress count
/// immediately on the projects list, before its own per-project fetch
/// resolves. Never a source of truth - always re-validated against the
/// freshly fetched task list on every `load()`.
public struct CachedProjectTaskSummary: Codable, Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// What `ProjectsListViewModel` needs in order to show each project's last
/// known task-completion tally immediately on the projects list, before its
/// own per-project fetch resolves, instead of a redacted placeholder, and
/// keep it fresh afterwards, without knowing anything about `UserDefaults`
/// or account ids. Implemented by `AccountProjectTaskSummaryCache` in the app
/// target and injected via `AppContainer`.
///
/// No expiry: the last known tallies are shown until `load()` reports fresh
/// ones, the same "last known good value, refreshed in background" shape as
/// `AccountTimezoneCaching`/`ServerVersionCaching`.
@MainActor
public protocol ProjectTaskSummaryCaching {
    func cachedTaskSummaries() -> [Int: CachedProjectTaskSummary]
    func setCachedTaskSummaries(_ summaries: [Int: CachedProjectTaskSummary])
}
