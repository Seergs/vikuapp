/// Request body for `VikunjaEndpoints.moveTaskToBucketV2`. The server takes
/// the target bucket and view from the URL and ignores any `bucket_id`/
/// `project_view_id` sent in the body (verified against a real instance's
/// `/api/v2/openapi.json` — `TaskBucket`), so only `task_id` is sent.
struct MoveTaskToBucketRequestDTO: Encodable {
    let taskId: Int

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
    }
}

/// Response of `VikunjaEndpoints.moveTaskToBucketV2`: the task as it stands
/// after the move, reflecting any done-state change from crossing into or
/// out of the view's done bucket — no second fetch needed.
struct TaskBucketResponseDTO: Decodable {
    let task: TaskDTO
}
