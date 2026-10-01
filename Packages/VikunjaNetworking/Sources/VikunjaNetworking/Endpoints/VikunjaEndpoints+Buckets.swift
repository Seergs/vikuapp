import Foundation

/// v2-only endpoint builders for Kanban: it never shipped on v1, so there's
/// no v1 counterpart to migrate. Kept in its own file, like
/// `VikunjaEndpoints+V2.swift`, so Kanban's surface stays easy to tell apart
/// from the per-resource v1/v2 migration.
extension VikunjaEndpoints {
    /// Lists a project's views so the Kanban one can be resolved by
    /// `view_kind`. Verified against a real instance's
    /// `/api/v2/openapi.json`: unlike `buckets/tasks` below, this list *is*
    /// the standard paginated envelope.
    static func projectViewsV2(projectID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(projectID)/views")
    }

    /// Returns every bucket of the given view, each populated with its
    /// tasks. Verified against a real instance's `/api/v2/openapi.json`.
    static func bucketsWithTasksV2(projectID: Int, viewID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(projectID)/views/\(viewID)/buckets/tasks")
    }

    /// Moves a task into `bucketID` within `viewID`. Moving into (or out of)
    /// the view's done bucket flips the task's done state server-side;
    /// moving into a bucket already at its WIP limit is rejected with 412.
    /// Verified against a real instance's `/api/v2/openapi.json`.
    static func moveTaskToBucketV2(projectID: Int, viewID: Int, bucketID: Int, taskID: Int) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/projects/\(projectID)/views/\(viewID)/buckets/\(bucketID)/tasks",
            method: .put,
            body: MoveTaskToBucketRequestDTO(taskId: taskID),
        )
    }

    /// Creates a task directly in `bucketID` via the regular task-create
    /// endpoint with `bucket_id` set, rather than a create-then-move pair of
    /// requests. Verified against a real instance's `/api/v2/openapi.json`.
    static func createTaskInBucketV2(projectID: Int, bucketID: Int, title: String) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/projects/\(projectID)/tasks",
            method: .post,
            body: CreateTaskInBucketDTO(title: title, bucketId: bucketID),
        )
    }
}
