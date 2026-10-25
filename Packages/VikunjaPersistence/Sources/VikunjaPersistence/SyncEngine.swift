import Foundation
import GRDB
import VikunjaCore

/// Keeps the local store's cache of each synced entity in step with the
/// server. Only pulling for now — draining locally queued mutations back to
/// the server is a later addition. Nothing constructs this in production
/// yet (no account-scoped `LocalStore` exists to hand it), so it's unused
/// until that wiring lands.
public actor SyncEngine {
    private let localStore: LocalStore
    private let projectRepository: ProjectRepositoryProtocol

    public init(localStore: LocalStore, projectRepository: ProjectRepositoryProtocol) {
        self.localStore = localStore
        self.projectRepository = projectRepository
    }

    /// Fetches every project from the server and reconciles it into the
    /// local store: upserts each one by its remote id, deletes a local row
    /// whose remote id is no longer present in the server's response
    /// (unless a mutation is still queued against it — that row might be a
    /// local edit the pull hasn't confirmed yet, not a real server-side
    /// deletion), and records this as the most recent full pull.
    ///
    /// Always a full reconciliation, never a partial one: the server has no
    /// way to filter the project list by `updated`, so there's no cheaper
    /// incremental fetch to fall back to between full pulls the way there
    /// will be for an entity whose list endpoint does support that.
    public func pullProjects() async throws {
        let remoteProjects = try await projectRepository.fetchProjects()
        let now = Date()

        try await localStore.write { db in
            let localRows = try ProjectRecord.fetchAll(db)
            let localIDByRemoteID = Self.reserveLocalIDs(for: remoteProjects, existing: localRows)

            try Self.upsertRows(for: remoteProjects, localIDByRemoteID: localIDByRemoteID, db: db)
            try Self.resolveParentLinks(for: remoteProjects, localIDByRemoteID: localIDByRemoteID, db: db)
            try Self.deleteMissingRows(
                localRows,
                stillPresentRemoteIDs: Set(remoteProjects.compactMap(\.id.remoteValue)),
                db: db,
            )

            try SyncStateRecord(entityType: .project, lastPulledAt: now).save(db)
        }
    }

    /// A localID for every remote project: an existing row's own, or a
    /// fresh `UUID` for one not seen before. Resolved up front so a child's
    /// parent link can be looked up below regardless of array order.
    private static func reserveLocalIDs(for remoteProjects: [Project], existing localRows: [ProjectRecord]) -> [Int: UUID] {
        var localIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: localRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, localIDByRemoteID[remoteID] == nil else { continue }
            localIDByRemoteID[remoteID] = UUID()
        }
        return localIDByRemoteID
    }

    /// Inserts or updates every remote project, with no parent link yet: a
    /// child can appear before its parent in `remoteProjects`, and
    /// `parentProjectLocalID`'s foreign key would reject pointing at a row
    /// that doesn't exist in the table yet.
    private static func upsertRows(
        for remoteProjects: [Project],
        localIDByRemoteID: [Int: UUID],
        db: Database,
    ) throws {
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            let row = ProjectRecord(
                localID: localID,
                remoteID: remoteID,
                title: project.title,
                description: project.description,
                isArchived: project.isArchived,
                isFavorite: project.isFavorite,
                parentProjectLocalID: nil,
                position: project.position,
                hexColor: project.hexColor,
                serverUpdatedAt: project.updated,
            )
            try row.save(db)
        }
    }

    /// Every row from `upsertRows` already exists by now, so setting a
    /// non-nil parent link in this second pass can't hit the foreign-key
    /// ordering problem that method avoids.
    private static func resolveParentLinks(
        for remoteProjects: [Project],
        localIDByRemoteID: [Int: UUID],
        db: Database,
    ) throws {
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            guard let parentLocalID = project.parentProjectID?.remoteValue.flatMap({ localIDByRemoteID[$0] }) else {
                continue
            }
            guard var row = try ProjectRecord.fetchOne(db, key: localID) else { continue }
            row.parentProjectLocalID = parentLocalID
            try row.save(db)
        }
    }

    /// Drops a local row whose remote id is no longer in the server's
    /// response, unless a mutation is still queued against it — that row
    /// might be a local edit the pull hasn't confirmed yet, not a real
    /// server-side deletion.
    private static func deleteMissingRows(
        _ localRows: [ProjectRecord],
        stillPresentRemoteIDs: Set<Int>,
        db: Database,
    ) throws {
        let queuedTargetLocalIDs = try Set(
            MutationQueueRecord.fetchAll(db)
                .filter { $0.status == .pending || $0.status == .inFlight }
                .map(\.targetLocalID),
        )
        for row in localRows {
            guard let remoteID = row.remoteID, !stillPresentRemoteIDs.contains(remoteID) else { continue }
            guard !queuedTargetLocalIDs.contains(row.localID) else { continue }
            try row.delete(db)
        }
    }
}
