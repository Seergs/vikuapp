/// A Vikunja saved filter, fetched/mutated through the server's own
/// `/filters` resource - distinct from `Project`, which only ever sees a
/// filter as the negative-id pseudo-project `/projects` mixes into its
/// listing (see `ProjectKind` and `Project.savedFilterID`).
public struct SavedFilterDetail: Equatable, Sendable {
    public let id: Int
    public let title: String
    public let description: String
    public let isFavorite: Bool
    /// The raw filter query this saved filter wraps (e.g. `priority >= 3 &&
    /// done = false`), in Vikunja's own filter syntax - see
    /// https://vikunja.io/docs/filters. Keep this raw value for API requests;
    /// use `FilterQueryFormatter` to resolve names for read-only presentation.
    /// Empty when the filter has no query set.
    public let query: String

    public init(id: Int, title: String, description: String, isFavorite: Bool, query: String) {
        self.id = id
        self.title = title
        self.description = description
        self.isFavorite = isFavorite
        self.query = query
    }
}
