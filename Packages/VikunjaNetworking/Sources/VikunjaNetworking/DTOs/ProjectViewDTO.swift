/// Tolerant mirror of one entry of `/api/v2/projects/{id}/views`. Only the
/// fields `VikunjaBucketRepository` needs to resolve a project's Kanban view
/// are modeled — verified against a real instance's `/api/v2/openapi.json`
/// (`ProjectView`).
struct ProjectViewDTO: Decodable {
    let id: Int
    let viewKind: String
    /// The id of the view's done bucket, if one is configured. Vikunja v2
    /// tracks "is this the done bucket" on the view, not on the bucket
    /// itself — there is no `is_done_bucket` field on `Bucket`.
    let doneBucketId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case viewKind = "view_kind"
        case doneBucketId = "done_bucket_id"
    }
}
