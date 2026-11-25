import Foundation
import GRDB
import VikunjaCore

struct KanbanViewCatalogRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kanbanViewCatalog"
    let projectLocalID: UUID
    let accountID: UUID
    let views: [KanbanViewSummary]
}

struct KanbanViewRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kanbanView"
    var localID: UUID
    var accountID: UUID
    var projectLocalID: UUID
    var remoteID: Int
    var mode: String
    /// Preserved server query. Any nonempty filter makes offline placement unsupported.
    var filterQuery: String
    var defaultBucketID: Int?
    var doneBucketID: Int?
    var lastCompletePullAt: Date?
    /// Bucket remote IDs mapped to canonical local task IDs in server response order.
    /// A legacy snapshot has no membership map and still reads its saved assignments.
    var automaticMembership: [Int: [UUID]]?
    var needsMembershipRefresh = false

    static func markAutomaticMembershipForRefresh(
        accountID: UUID, projectIDs: Set<UUID>, db: Database,
    ) throws {
        guard !projectIDs.isEmpty else { return }
        try filter(Column("accountID") == accountID)
            .filter(projectIDs.contains(Column("projectLocalID")))
            .filter(Column("mode") == "filter" && Column("lastCompletePullAt") != nil)
            .filter(Column("needsMembershipRefresh") == false)
            .updateAll(db, Column("needsMembershipRefresh").set(to: true))
    }
}

struct KanbanBucketRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kanbanBucket"
    var localID: UUID
    var accountID: UUID
    var projectLocalID: UUID
    var viewLocalID: UUID
    var remoteID: Int
    var title: String
    var position: Double
    var limit: Int
    var serverCount: Int
}

struct KanbanAssignmentRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kanbanAssignment"
    var accountID: UUID
    var projectLocalID: UUID
    var viewLocalID: UUID
    var bucketLocalID: UUID
    var taskLocalID: UUID
    var position: Double
}
