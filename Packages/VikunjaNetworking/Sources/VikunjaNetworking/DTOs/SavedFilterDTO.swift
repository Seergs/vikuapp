/// Mirrors Vikunja's `SavedFilter`/`SavedFilterReadBody` - same field names on
/// both API versions. Also doubles as the v1 update body (full overwrite):
/// `description`/`isFavorite` must be round-tripped from a prior GET so the
/// server's blind `Cols("title", "description", "is_favorite", ...)` write
/// doesn't zero them out. `filters` (the saved query) and other read-only
/// fields are deliberately not modeled - this app only ever reads/writes
/// `title` today.
struct SavedFilterDTO: Codable {
    let id: Int
    let title: String
    let description: String?
    let isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case isFavorite = "is_favorite"
    }
}

/// v2's `PATCH /filters/{id}` body (`application/merge-patch+json`, RFC 7396):
/// only the keys present here get applied server-side, so renaming never
/// risks clobbering the filter's description/favorite/query the way v1's
/// full-overwrite `SavedFilterDTO` would without a prior GET.
struct SavedFilterTitlePatchDTO: Codable {
    let title: String
}
