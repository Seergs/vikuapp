public protocol BucketRepositoryProtocol: Sendable {
    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload
    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket]
    func moveTask(taskID: Int, toBucketID: Int, projectID: Int) async throws -> VikunjaTask
    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask
}
