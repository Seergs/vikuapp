/// Account-scoped structured reads. Implementations resolve names and effective
/// task state from one local snapshot, without triggering synchronization.
public protocol TaskSearchRepositoryProtocol: Sendable {
    func searchTasks(matching query: TaskSearchQuery) async throws -> [VikunjaTask]
}
