import VikunjaCore

public final class VikunjaFilterRepositoryV2: FilterRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchFilter(id: Int) async throws -> SavedFilterDetail {
        let dto: SavedFilterDTO = try await client.send(VikunjaEndpoints.filterV2(id: id))
        return SavedFilterMapper.toDomain(dto)
    }

    public func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail {
        let endpoint = try VikunjaEndpoints.renameFilterV2(id: id, title: title)
        let dto: SavedFilterDTO = try await client.send(endpoint)
        return SavedFilterMapper.toDomain(dto)
    }

    public func deleteFilter(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteFilterV2(id: id))
    }
}
