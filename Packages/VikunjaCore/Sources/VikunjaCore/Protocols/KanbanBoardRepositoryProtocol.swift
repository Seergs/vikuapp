/// Snapshot queries never perform network work; downloads use an injected SyncTriggering source.
/// Commands follow the source's capabilities: project boards commit durable local intent,
/// while online-only sources await server confirmation and never enqueue offline writes.
public protocol KanbanBoardRepositoryProtocol: Sendable {
    /// Account-scoped proof of prior Kanban support, including other projects.
    func hasCachedKanbanSupport() async throws -> Bool
    func moveTask(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask
    func createTask(title: String, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask
    func fetchBoard(projectID: EntityID, viewID: Int?) async throws -> KanbanBoardSnapshot
}
