/// Mirrors Vikunja's `SavedFilter`/`SavedFilterReadBody` - same field names on
/// both API versions. Also doubles as the v1 update body (full overwrite):
/// `description`/`isFavorite` must be round-tripped from a prior GET so the
/// server's blind `Cols("title", "description", "is_favorite", ...)` write
/// doesn't zero them out. `filters` is read-only here (`VikunjaFilterRepository
/// .renameFilter` always encodes it as `nil`, which Swift's synthesized
/// `Encodable` omits from the JSON entirely - Vikunja's v1 `Update` leaves a
/// filter's query alone when the key is absent, same reasoning as
/// `description`/`isFavorite` but the opposite fix: preserve by omitting,
/// not by round-tripping).
struct SavedFilterDTO: Codable {
    let id: Int
    let title: String
    let description: String?
    let isFavorite: Bool?
    let filters: SavedFilterQueryDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case filters
        case isFavorite = "is_favorite"
    }
}

/// The one field of Vikunja's `TaskCollection` this app reads: the raw filter
/// query string. The rest (`s`, `sort_by`, `order_by`, `filter_include_nulls`)
/// isn't modeled - nothing here reads or writes it.
struct SavedFilterQueryDTO: Codable {
    let filter: String?
}

/// v2's `PATCH /filters/{id}` body (`application/merge-patch+json`, RFC 7396):
/// only the keys present here get applied server-side, so renaming never
/// risks clobbering the filter's description/favorite/query the way v1's
/// full-overwrite `SavedFilterDTO` would without a prior GET.
struct SavedFilterTitlePatchDTO: Codable {
    let title: String
}
