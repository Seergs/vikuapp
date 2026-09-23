/// Unwraps v2's list-response envelope (`{items, total, page, per_page,
/// total_pages}`) — v1's equivalent is a bare array plus `x-pagination-*`
/// response headers, so this has no v1 counterpart.
///
/// Shape verified against a real instance's `/api/v2/openapi.json`
/// (`PaginatedProject` etc.): `items` is nullable (an empty result page can
/// come back as `null` rather than `[]`), so this decodes it leniently and
/// normalizes that to an empty array.
struct APIv2Envelope<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let total: Int
    let page: Int
    let perPage: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case perPage = "per_page"
        case totalPages = "total_pages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        self.total = try container.decode(Int.self, forKey: .total)
        self.page = try container.decode(Int.self, forKey: .page)
        self.perPage = try container.decode(Int.self, forKey: .perPage)
        self.totalPages = try container.decode(Int.self, forKey: .totalPages)
    }
}
