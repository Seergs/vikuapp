/// Local queries and durable commands. Uploads are scheduled after committing local writes.
public protocol KanbanBoardRepositoryProtocol: Sendable {
    func moveTask(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask
    func createTask(title: String, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask
    func fetchBoard(projectID: EntityID, viewID: Int) async throws -> KanbanBoardSnapshot
}
