import Foundation
import GRDB

/// Row shape of the `label` table: the local cache of a label. Mapping
/// to/from the `VikunjaCore.Label` domain model belongs to the repository
/// that reads/writes this record, not here.
struct LabelRecord: Codable, Equatable, Sendable {
    var localID: UUID
    var accountID: UUID
    var remoteID: Int?
    var title: String
    var hexColor: String
}

extension LabelRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "label"
}
