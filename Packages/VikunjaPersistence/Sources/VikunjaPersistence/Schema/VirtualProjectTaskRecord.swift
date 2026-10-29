import Foundation
import GRDB

/// A task can appear in a virtual project without changing its owning
/// `TaskRecord.projectLocalID`. This row stores that additional membership.
struct VirtualProjectTaskRecord: Codable, Equatable, Sendable {
    var accountID: UUID
    var projectLocalID: UUID
    var taskLocalID: UUID
    var position: Int
}

extension VirtualProjectTaskRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "virtualProjectTask"
}
