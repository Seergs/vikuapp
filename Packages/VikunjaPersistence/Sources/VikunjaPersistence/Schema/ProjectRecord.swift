import Foundation
import GRDB

/// Row shape of the `project` table: the local cache of a project plus the
/// bookkeeping offline sync needs. Mapping to/from the `VikunjaCore.Project`
/// domain model belongs to the repository that reads/writes this record,
/// not here.
struct ProjectRecord: Codable, Equatable, Sendable {
    var localID: UUID
    var accountID: UUID
    var remoteID: Int?
    var title: String
    var description: String?
    var isArchived: Bool
    var isFavorite: Bool
    var parentProjectLocalID: UUID?
    var position: Double
    var hexColor: String
    var serverUpdatedAt: Date?
}

extension ProjectRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "project"
}
