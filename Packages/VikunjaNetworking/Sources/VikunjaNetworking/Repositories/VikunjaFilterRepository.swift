import VikunjaCore

public final class VikunjaFilterRepository: FilterRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchFilter(id: Int) async throws -> SavedFilterDetail {
        let dto: SavedFilterDTO = try await client.send(VikunjaEndpoints.filter(id: id))
        return SavedFilterMapper.toDomain(dto)
    }

    /// v1 has no PATCH for filters, so a rename must fetch first and
    /// round-trip `description`/`isFavorite` - see `SavedFilterDTO`'s doc
    /// comment. `VikunjaFilterRepositoryV2.renameFilter` needs none of this.
    public func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail {
        let current: SavedFilterDTO = try await client.send(VikunjaEndpoints.filter(id: id))
        let endpoint = try VikunjaEndpoints.updateFilter(
            id: id,
            dto: SavedFilterDTO(id: id, title: title, description: current.description, isFavorite: current.isFavorite),
        )
        let dto: SavedFilterDTO = try await client.send(endpoint)
        return SavedFilterMapper.toDomain(dto)
    }

    public func deleteFilter(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteFilter(id: id))
    }
}
