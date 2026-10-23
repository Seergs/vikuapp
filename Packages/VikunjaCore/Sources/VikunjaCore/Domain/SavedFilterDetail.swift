/// A Vikunja saved filter, fetched/mutated through the server's own
/// `/filters` resource - distinct from `Project`, which only ever sees a
/// filter as the negative-id pseudo-project `/projects` mixes into its
/// listing (see `ProjectKind` and `Project.savedFilterID`).
///
/// Deliberately doesn't model the filter's query (`TaskCollection` server-side)
/// yet - no screen reads or writes it. Add it here when that UI exists.
public struct SavedFilterDetail: Equatable, Sendable {
    public let id: Int
    public let title: String
    public let description: String
    public let isFavorite: Bool

    public init(id: Int, title: String, description: String, isFavorite: Bool) {
        self.id = id
        self.title = title
        self.description = description
        self.isFavorite = isFavorite
    }
}
