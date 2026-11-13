import Foundation
import VikunjaCore

extension APIClient {
    /// Return a complete catalog so callers can safely reconcile missing rows.
    func sendAllPagesV1<Item: Decodable & Sendable>(
        endpoint: @Sendable (Int) -> Endpoint,
    ) async throws -> [Item] {
        try Task.checkCancellation()
        let (firstPage, response): ([Item], HTTPURLResponse) = try await sendWithResponse(endpoint(1))
        let header = response.value(forHTTPHeaderField: "x-pagination-total-pages") ?? "1"
        guard let totalPages = Int(header), totalPages >= 0,
              totalPages > 0 || firstPage.isEmpty
        else { throw VikunjaError.decoding("Invalid pagination metadata") }

        var items = firstPage
        if totalPages > 1 {
            guard !firstPage.isEmpty else { throw VikunjaError.decoding("Incomplete paginated download") }
            for page in 2 ... totalPages {
                try Task.checkCancellation()
                let nextPage: [Item] = try await send(endpoint(page))
                guard !nextPage.isEmpty else { throw VikunjaError.decoding("Incomplete paginated download") }
                items += nextPage
            }
        }
        try Task.checkCancellation()
        return items
    }

    func sendAllPagesV2<Item: Decodable & Sendable>(
        endpoint: @Sendable (Int) -> Endpoint,
    ) async throws -> [Item] {
        try Task.checkCancellation()
        let firstPage: APIv2Envelope<Item> = try await send(endpoint(1))
        guard firstPage.page == 1, firstPage.totalPages >= 0, firstPage.total >= 0,
              firstPage.totalPages > 0 || firstPage.items.isEmpty
        else { throw VikunjaError.decoding("Invalid pagination metadata") }

        var items = firstPage.items
        if firstPage.totalPages > 1 {
            guard !items.isEmpty else { throw VikunjaError.decoding("Incomplete paginated download") }
            for page in 2 ... firstPage.totalPages {
                try Task.checkCancellation()
                let nextPage: APIv2Envelope<Item> = try await send(endpoint(page))
                guard nextPage.page == page, nextPage.total == firstPage.total,
                      nextPage.totalPages == firstPage.totalPages, !nextPage.items.isEmpty
                else { throw VikunjaError.decoding("Inconsistent paginated download") }
                items += nextPage.items
            }
        }
        try Task.checkCancellation()
        guard items.count == firstPage.total else { throw VikunjaError.decoding("Incomplete paginated download") }
        return items
    }
}
