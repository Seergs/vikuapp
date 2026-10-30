import Foundation
import GRDB

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
