/// Placement following a completion change in a manual Kanban view.
public enum KanbanCompletion {
    /// Reopening only leaves the done bucket. Missing placement (creation or a
    /// project change) starts in the default bucket, or the leftmost fallback.
    /// Nil means the view has no applicable destination.
    public static func destination(
        isDone: Bool, currentBucketID: Int?, doneBucketID: Int?,
        defaultBucketID: Int?, firstBucketID: Int?,
    ) -> Int? {
        // Vikunja also represents an unconfigured bucket with zero.
        let doneBucketID = doneBucketID.flatMap { $0 > 0 ? $0 : nil }
        let defaultBucketID = defaultBucketID.flatMap { $0 > 0 ? $0 : nil }
        if isDone, let doneBucketID {
            return doneBucketID
        }
        if let currentBucketID {
            guard !isDone, currentBucketID == doneBucketID else { return currentBucketID }
        }
        return defaultBucketID ?? firstBucketID
    }
}
