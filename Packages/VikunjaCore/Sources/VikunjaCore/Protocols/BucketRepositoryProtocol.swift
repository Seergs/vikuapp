public protocol BucketRepositoryProtocol: Sendable {
    /// All Kanban views of the project, in server display order.
    func fetchKanbanViews(projectID: Int) async throws -> [KanbanViewSummary]
    /// Absolute per-view position write, separate from bucket membership.
    func setTaskPosition(taskID: Int, viewID: Int, position: Double) async throws -> TaskViewPosition
    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload
    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket]
    func moveTask(taskID: Int, toBucketID: Int, projectID: Int, viewID: Int?) async throws -> VikunjaTask
    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask
}

public extension BucketRepositoryProtocol {
    func moveTask(taskID: Int, toBucketID: Int, projectID: Int) async throws -> VikunjaTask {
        try await moveTask(taskID: taskID, toBucketID: toBucketID, projectID: projectID, viewID: nil)
    }
}
