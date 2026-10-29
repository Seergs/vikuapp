import Foundation
import GRDB
import VikunjaCore

/// The part of a saved filter that `/projects` does not provide: its raw
/// query and the time that query was last fetched. Presentation fields remain
/// owned by the linked `ProjectRecord`.
struct SavedFilterRecord: Codable, Equatable, Sendable {
    var projectLocalID: UUID
    var accountID: UUID
    var remoteID: Int
    var query: String
    /// `nil` means this row was backfilled from `/projects`, but its query
    /// has not yet been fetched from `/filters`.
    var lastPulledAt: Date?
}

extension SavedFilterRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "savedFilter"

    static func fetch(projectLocalID: UUID, db: Database) throws -> Self? {
        try filter(Column("projectLocalID") == projectLocalID).fetchOne(db)
    }

    /// Persists the server query and marks the cache as populated. Keeping
    /// these writes together prevents an empty, valid query from being
    /// mistaken for a backfilled row that has not been fetched yet.
    mutating func storeQuery(_ query: String, pulledAt: Date, db: Database) throws {
        self.query = query
        lastPulledAt = pulledAt
        try save(db)
    }

    /// Builds the detail from the canonical project presentation fields and
    /// this record's cached query. A mismatch means the caller paired rows
    /// from different saved filters, so don't return a misleading detail.
    func detail(project: Project) -> SavedFilterDetail? {
        guard project.savedFilterID == remoteID else { return nil }
        return SavedFilterDetail(
            id: remoteID,
            title: project.title,
            description: project.description ?? "",
            isFavorite: project.isFavorite,
            query: query,
        )
    }
}
