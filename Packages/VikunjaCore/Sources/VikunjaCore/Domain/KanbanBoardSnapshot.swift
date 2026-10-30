import Foundation

/// A missing snapshot is different from a downloaded board with no cards.
public enum KanbanBoardSnapshot: Equatable, Sendable {
    case waitingForProject
    case unavailable
    case available(KanbanBoard)
}

public struct KanbanBoard: Equatable, Sendable {
    public let viewID: Int
    public let buckets: [KanbanBucket]
    public let defaultBucketID: Int?
    public let supportsOfflineWrites: Bool
    public let lastPulledAt: Date

    public init(
        viewID: Int, buckets: [KanbanBucket], defaultBucketID: Int?,
        supportsOfflineWrites: Bool, lastPulledAt: Date,
    ) {
        self.viewID = viewID
        self.buckets = buckets
        self.defaultBucketID = defaultBucketID
        self.supportsOfflineWrites = supportsOfflineWrites
        self.lastPulledAt = lastPulledAt
    }
}
