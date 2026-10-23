/// Talks to Vikunja's own `/filters` resource, by a saved filter's real,
/// positive id - never the negative pseudo-project id `ProjectRepositoryProtocol`
/// sees it as through `/projects`. Callers translate between the two with
/// `Project.savedFilterID`.
///
/// No `updateColor`/`create`: Vikunja's saved filter has no color field on
/// either API version (verified against a live v2 instance's OpenAPI spec and
/// the server's own model source - `ToProject()` never sets `HexColor`, and
/// `Update()` never persists one), and this app doesn't create filters.
public protocol FilterRepositoryProtocol: Sendable {
    func fetchFilter(id: Int) async throws -> SavedFilterDetail
    func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail
    func deleteFilter(id: Int) async throws
}
