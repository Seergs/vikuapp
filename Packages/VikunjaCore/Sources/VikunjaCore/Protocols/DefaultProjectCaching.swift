/// A display-only snapshot of an account's Vikunja default project: just
/// enough (id, title, hex color) for `QuickAddTaskViewModel` to render its
/// project field before its own fetch resolves. Never a source of truth for
/// what the default project actually is — that's always the server's
/// `User.defaultProjectID`, re-validated against the freshly loaded project
/// list on every `load()`.
public struct CachedDefaultProject: Codable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let hexColor: String

    public init(id: Int, title: String, hexColor: String) {
        self.id = id
        self.title = title
        self.hexColor = hexColor
    }
}

/// What `QuickAddTaskViewModel` needs in order to show the last known
/// default project immediately (no spinner) and keep it fresh, without
/// knowing anything about `UserDefaults` or account ids. Implemented by
/// `AccountDefaultProjectCache` in the app target, scoped to one account,
/// and injected via `AppContainer`, the same way `ToastPresenting` is.
@MainActor
public protocol DefaultProjectCaching {
    func cachedDefaultProject() -> CachedDefaultProject?
    func setCachedDefaultProject(_ project: CachedDefaultProject?)
}
