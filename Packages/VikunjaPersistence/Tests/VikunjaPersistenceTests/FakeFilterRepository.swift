import VikunjaCore

final class FakeFilterRepository: FilterRepositoryProtocol, @unchecked Sendable {
    var filters: [Int: SavedFilterDetail] = [:]
    var fetchError: Error?
    var renameError: Error?
    var deleteError: Error?
    private(set) var fetchedIDs: [Int] = []
    private(set) var renamed: [(id: Int, title: String)] = []
    private(set) var deletedIDs: [Int] = []

    func fetchFilter(id: Int) async throws -> SavedFilterDetail {
        fetchedIDs.append(id)
        if let fetchError {
            throw fetchError
        }
        guard let filter = filters[id] else { throw VikunjaError.notFound }
        return filter
    }

    func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail {
        if let renameError {
            throw renameError
        }
        guard let current = filters[id] else { throw VikunjaError.notFound }
        let updated = SavedFilterDetail(
            id: id, title: title, description: current.description,
            isFavorite: current.isFavorite, query: current.query,
        )
        renamed.append((id, title))
        filters[id] = updated
        return updated
    }

    func deleteFilter(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        guard filters.removeValue(forKey: id) != nil else { throw VikunjaError.notFound }
        deletedIDs.append(id)
    }
}
