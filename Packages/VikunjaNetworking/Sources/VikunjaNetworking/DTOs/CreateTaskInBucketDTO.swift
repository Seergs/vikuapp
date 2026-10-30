/// Request body for `VikunjaEndpoints.createTaskInBucketV2`. Vikunja's v2
/// `Task` schema accepts a writable `bucket_id` at creation time (verified
/// against a real instance's `/api/v2/openapi.json`), so the task lands
/// directly in the target bucket without a separate move call.
struct CreateTaskInBucketDTO: Encodable {
    let task: TaskDTO
    let bucketId: Int

    enum CodingKeys: String, CodingKey {
        case bucketId = "bucket_id"
    }

    func encode(to encoder: Encoder) throws {
        try task.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bucketId, forKey: .bucketId)
    }
}
