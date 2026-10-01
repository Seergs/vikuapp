/// Tolerant mirror of one entry of
/// `/api/v2/projects/{id}/views/{view}/buckets/tasks`. Field names verified
/// against a real instance's `/api/v2/openapi.json` (`Bucket`). Has no
/// `is_done_bucket` field — see `ProjectViewDTO.doneBucketId`.
struct BucketDTO: Decodable {
    let id: Int
    let title: String
    let limit: Int
    let tasks: [TaskDTO]?
}

/// `/api/v2/projects/{id}/views/{view}/buckets/tasks`'s response envelope.
/// Unlike every other v2 list endpoint, this is **not** paginated (the
/// number of buckets follows the view's bucket configuration, not a page
/// size) so it has no `page`/`per_page`/`total_pages` and can't reuse
/// `APIv2Envelope` — verified against a real instance's
/// `/api/v2/openapi.json` (`BucketsWithTasksBodyBody`).
struct BucketsWithTasksResponseDTO: Decodable {
    let items: [BucketDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeIfPresent([BucketDTO].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}
