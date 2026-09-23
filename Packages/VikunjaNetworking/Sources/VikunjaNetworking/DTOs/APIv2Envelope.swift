/// Unwraps v2's list-response envelope (`{items, total, page, per_page,
/// total_pages}`) — v1's equivalent is a bare array plus `x-pagination-*`
/// response headers, so this has no v1 counterpart.
struct APIv2Envelope<Item: Decodable>: Decodable {
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
}
