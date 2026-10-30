/// Tolerant mirror of one entry of
/// `/api/v2/projects/{id}/views/{view}/buckets/tasks`. Field names verified
/// against a real instance's `/api/v2/openapi.json` (`Bucket`). Has no
/// `is_done_bucket` field — see `ProjectViewDTO.doneBucketId`.
struct BucketDTO: Decodable {
    let projectViewID: Int?
    let position: Double?
    let id: Int
    let title: String
    let limit: Int
    let count: Int?
    let tasks: [TaskDTO]?
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case limit
        case count
        case tasks
        case position
        case projectViewID = "project_view_id"
    }
}

/// `/api/v2/projects/{id}/views/{view}/buckets/tasks`'s response envelope.
/// The buckets themselves are **not** paginated (the
/// number of buckets follows the view's bucket configuration, not a page
/// size) so it has no `page`/`per_page`/`total_pages` and can't reuse
/// `APIv2Envelope`. Tasks inside each bucket are paginated via `page`,
/// with each bucket's `count` reporting its total tasks. The envelope shape
/// matches `/api/v2/openapi.json` (`BucketsWithTasksBodyBody`); task paging
/// follows the server's `TaskCollection` and `GetTasksInBuckets` implementation.
struct BucketsWithTasksResponseDTO: Decodable {
    let items: [BucketDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.items) else {
            throw DecodingError.keyNotFound(CodingKeys.items, .init(
                codingPath: decoder.codingPath, debugDescription: "Missing Kanban items envelope",
            ))
        }
        self.items = try container.decodeIfPresent([BucketDTO].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}
