/// Complete server snapshot, handed to persistence only after every page succeeds.
public struct KanbanDownload: Sendable {
    public let viewID: Int
    public let mode: String
    public let filterQuery: String
    public let defaultBucketID: Int?
    public let doneBucketID: Int?
    public let buckets: [KanbanBucket]

    public init(
        viewID: Int, mode: String, filterQuery: String, defaultBucketID: Int?,
        doneBucketID: Int?, buckets: [KanbanBucket],
    ) {
        self.viewID = viewID
        self.mode = mode
        self.filterQuery = filterQuery
        self.defaultBucketID = defaultBucketID
        self.doneBucketID = doneBucketID
        self.buckets = buckets
    }
}
