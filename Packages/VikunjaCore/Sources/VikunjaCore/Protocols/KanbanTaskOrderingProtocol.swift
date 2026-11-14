/// Ordering changes never move a task between buckets or edit its other fields.
/// Durable project boards accept local intent offline. Online-only boards await
/// confirmation. The bucket identifies the expected current placement; a remote
/// bucket change must not silently turn a reorder into a bucket move.
public protocol KanbanTaskOrderingProtocol: Sendable {
    func reorderTask(
        taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int, placement: KanbanTaskPlacement,
    ) async throws
}

public extension KanbanTaskOrderingProtocol {
    func moveTaskToTop(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws {
        try await reorderTask(taskID: taskID, projectID: projectID, viewID: viewID, bucketID: bucketID, placement: .top)
    }

    func moveTaskToBottom(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws {
        try await reorderTask(
            taskID: taskID,
            projectID: projectID,
            viewID: viewID,
            bucketID: bucketID,
            placement: .bottom,
        )
    }
}
