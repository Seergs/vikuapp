/// A display snapshot of the project or saved filter pinned as the Home
/// tab's content: id, title, hex color, and `kind` (so the Settings picker
/// and the Home tab can label a filter as a filter rather than an anonymous
/// negative id — see `ProjectKind`). `nil` means "Today", the
/// default/fallback selection; there's nothing to cache for that case.
public struct CachedHomeSelection: Codable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let hexColor: String
    public let kind: ProjectKind

    public init(id: Int, title: String, hexColor: String, kind: ProjectKind) {
        self.id = id
        self.title = title
        self.hexColor = hexColor
        self.kind = kind
    }
}

/// What the Settings "Home Screen" row needs in order to read/write the
/// pinned Home selection, without knowing anything about `UserDefaults` or
/// account ids. Implemented by `AccountHomeSelectionCache` in the app
/// target, scoped to one account, and injected via `AppContainer` the same
/// way `DefaultProjectCaching` is.
///
/// Unlike `DefaultProjectCaching`, which mirrors a server-side value
/// (`User.defaultProjectID`), this cache *is* the source of truth: pinning a
/// Home tab selection has no server-side counterpart, so there's nothing to
/// reconcile against on load.
@MainActor
public protocol HomeSelectionCaching {
    func cachedHomeSelection() -> CachedHomeSelection?
    func setCachedHomeSelection(_ selection: CachedHomeSelection?)
}

/// A `HomeSelectionCaching` that always reports "Today" (no pin) and ignores
/// writes. The default for previews, tests, and any screen that hasn't
/// opted into the pinned-Home feature yet — mirrors `NoopToastPresenter`/
/// `NoopHapticFeedback`.
public struct NoopHomeSelectionCaching: HomeSelectionCaching {
    public init() {}
    public func cachedHomeSelection() -> CachedHomeSelection? {
        nil
    }

    public func setCachedHomeSelection(_ selection: CachedHomeSelection?) {}
}
