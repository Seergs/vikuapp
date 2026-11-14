import Foundation
import VikunjaCore

extension APIClient {
    /// Return a complete catalog so callers can safely reconcile missing rows.
    /// `countedItem` excludes supplemental entries outside the server pagination,
    /// such as Favorites and saved-filter pseudo-projects appended to every page.
    func sendAllPagesV1<Item: Decodable & Sendable>(
        countedItem: @Sendable (Item) -> Bool = { _ in true },
        endpoint: @Sendable (Int) -> Endpoint,
    ) async throws -> [Item] {
        try Task.checkCancellation()
        let (firstPage, response): ([Item], HTTPURLResponse) = try await sendWithResponse(endpoint(1))
        let header = response.value(forHTTPHeaderField: "x-pagination-total-pages") ?? "1"
        guard let totalPages = Int(header), totalPages >= 0,
              totalPages > 0 || !firstPage.contains(where: countedItem)
        else { throw VikunjaError.decoding("Invalid pagination metadata") }

        var items = firstPage
        if totalPages > 1 {
            guard firstPage.contains(where: countedItem) else {
                throw VikunjaError.decoding("Incomplete paginated download")
            }
            for page in 2 ... totalPages {
                try Task.checkCancellation()
                let nextPage: [Item] = try await send(endpoint(page))
                guard nextPage.contains(where: countedItem) else {
                    throw VikunjaError.decoding("Incomplete paginated download")
                }
                items += nextPage
            }
        }
        try Task.checkCancellation()
        return items
    }

    func sendAllPagesV2<Item: Decodable & Sendable>(
        countedItem: @Sendable (Item) -> Bool = { _ in true },
        endpoint: @Sendable (Int) -> Endpoint,
    ) async throws -> [Item] {
        try Task.checkCancellation()
        let firstPage: APIv2Envelope<Item> = try await send(endpoint(1))
        guard firstPage.page == 1, firstPage.totalPages >= 0, firstPage.total >= 0,
              firstPage.totalPages > 0 || !firstPage.items.contains(where: countedItem)
        else { throw VikunjaError.decoding("Invalid pagination metadata") }

        var items = firstPage.items
        if firstPage.totalPages > 1 {
            guard items.contains(where: countedItem) else {
                throw VikunjaError.decoding("Incomplete paginated download")
            }
            for page in 2 ... firstPage.totalPages {
                try Task.checkCancellation()
                let nextPage: APIv2Envelope<Item> = try await send(endpoint(page))
                guard nextPage.page == page, nextPage.total == firstPage.total,
                      nextPage.totalPages == firstPage.totalPages, nextPage.items.contains(where: countedItem)
                else { throw VikunjaError.decoding("Inconsistent paginated download") }
                items += nextPage.items
            }
        }
        try Task.checkCancellation()
        guard items.filter(countedItem).count == firstPage.total else {
            throw VikunjaError.decoding("Incomplete paginated download")
        }
        return items
    }
}
