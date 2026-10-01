/// Request body for `VikunjaEndpoints.createTaskInBucketV2`. Vikunja's v2
/// `Task` schema accepts a writable `bucket_id` at creation time (verified
/// against a real instance's `/api/v2/openapi.json`), so the task lands
/// directly in the target bucket without a separate move call.
struct CreateTaskInBucketDTO: Encodable {
    let title: String
    let bucketId: Int

    enum CodingKeys: String, CodingKey {
        case title
        case bucketId = "bucket_id"
    }
}
