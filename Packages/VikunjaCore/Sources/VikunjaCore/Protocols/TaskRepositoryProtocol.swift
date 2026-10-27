public protocol TaskRepositoryProtocol: Sendable {
    func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask]
    func fetchTask(id: EntityID) async throws -> VikunjaTask
    func create(_ task: VikunjaTask) async throws -> VikunjaTask
    func update(_ task: VikunjaTask) async throws -> VikunjaTask
    func delete(id: EntityID) async throws
    /// Searches every task the account can see (not scoped to one project) —
    /// used to find a candidate task to relate the current one to.
    func searchTasks(query: String) async throws -> [VikunjaTask]
}
