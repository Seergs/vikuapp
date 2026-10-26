import Foundation
import GRDB
import VikunjaCore

/// Keeps one account's slice of the local store's cache in step with the
/// server: pulls the server's state in, and drains that account's locally
/// queued mutations back out. Nothing constructs this in production yet
/// (nothing queues a mutation for it to drain), so it's unused until the
/// repository and coordinator that will drive it land.
public actor SyncEngine {
    private let localStore: LocalStore
    private let projectRepository: ProjectRepositoryProtocol
    /// `InstanceAccount.id` — every row this engine reads or writes is
    /// scoped to this one account, since `LocalStore`'s tables hold every
    /// saved account's data together rather than one database file each.
    private let accountID: UUID

    public init(localStore: LocalStore, projectRepository: ProjectRepositoryProtocol, accountID: UUID) {
        self.localStore = localStore
        self.projectRepository = projectRepository
        self.accountID = accountID
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
            let localRows = try ProjectRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            let localIDByRemoteID = Self.reserveLocalIDs(for: remoteProjects, existing: localRows)

            try Self.upsertRows(
                for: remoteProjects, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID, db: db,
            )
            try Self.resolveParentLinks(for: remoteProjects, localIDByRemoteID: localIDByRemoteID, db: db)
            try Self.deleteMissingRows(
                localRows,
                stillPresentRemoteIDs: Set(remoteProjects.compactMap(\.id.remoteValue)),
                accountID: self.accountID,
                db: db,
            )

            try SyncStateRecord(accountID: self.accountID, entityType: .project, lastPulledAt: now).save(db)
        }
    }

    /// A localID for every remote project: an existing row's own, or a
    /// fresh `UUID` for one not seen before. Resolved up front so a child's
    /// parent link can be looked up below regardless of array order.
    /// `existing` is already scoped to this engine's account, so `remoteID`
    /// only needs to be unique within it, not across every saved account.
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
        accountID: UUID,
        localIDByRemoteID: [Int: UUID],
        db: Database,
    ) throws {
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            let row = ProjectRecord(
                localID: localID,
                accountID: accountID,
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
    /// server-side deletion. `localRows` is already scoped to `accountID`.
    private static func deleteMissingRows(
        _ localRows: [ProjectRecord],
        stillPresentRemoteIDs: Set<Int>,
        accountID: UUID,
        db: Database,
    ) throws {
        let queuedTargetLocalIDs = try Set(
            MutationQueueRecord.fetchAll(db)
                .filter { $0.accountID == accountID && ($0.status == .pending || $0.status == .inFlight) }
                .map(\.targetLocalID),
        )
        for row in localRows {
            guard let remoteID = row.remoteID, !stillPresentRemoteIDs.contains(remoteID) else { continue }
            guard !queuedTargetLocalIDs.contains(row.localID) else { continue }
            try row.delete(db)
        }
    }

    // MARK: - Draining queued mutations

    enum DrainError: Error {
        /// `payload` was nil, or didn't decode as the shape its `operation` expects.
        case invalidPayload
    }

    /// Replays every queued, non-conflicted project mutation against the
    /// server, oldest first. A `create`/`update` whose payload references a
    /// parent project that hasn't itself synced yet (no remote id) is left
    /// in the queue for a later drain pass — by processing in the order
    /// mutations were queued, a parent's own `create` (necessarily queued
    /// before any child that references it) has already run earlier in
    /// this same pass if it's going to succeed at all, so this only
    /// actually defers anything when the parent's own create is still
    /// failing. One item's failure doesn't stop the rest from draining.
    public func drainProjectMutations() async throws {
        let items = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .project
                        && $0.status == .pending && !$0.needsConflictResolution
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
        for item in items {
            await drain(item)
        }
    }

    private func drain(_ item: MutationQueueRecord) async {
        do {
            switch item.operation {
            case .create: try await drainCreate(item)
            case .update: try await drainUpdate(item)
            case .delete: try await drainDelete(item)
            }
        } catch {
            await markFailed(item, error: error)
        }
    }

    private func drainCreate(_ item: MutationQueueRecord) async throws {
        guard let payload: ProjectCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let resolvedParentID = try await localStore.read { db in
            try Self.resolveRemoteID(forLocalID: payload.parentProjectLocalID, db: db)
        }
        guard payload.parentProjectLocalID == nil || resolvedParentID != nil else {
            return // The parent hasn't synced yet — retry this item on a later pass.
        }
        let project = Project(
            id: .local(item.targetLocalID),
            title: payload.title,
            description: payload.description,
            isArchived: payload.isArchived,
            isFavorite: payload.isFavorite,
            parentProjectID: resolvedParentID.map(EntityID.remote),
            position: payload.position,
            hexColor: payload.hexColor,
        )
        let created = try await projectRepository.create(project)
        try await applyPushResult(created, deleting: item)
    }

    private func drainUpdate(_ item: MutationQueueRecord) async throws {
        guard let payload: ProjectCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let (currentRow, resolvedParentID) = try await localStore.read { db in
            let row = try ProjectRecord.fetchOne(db, key: item.targetLocalID)
            let parentID = try Self.resolveRemoteID(forLocalID: payload.parentProjectLocalID, db: db)
            return (row, parentID)
        }
        guard let currentRow, let remoteID = currentRow.remoteID else {
            return // Not synced yet — there's nothing server-side to update.
        }
        guard payload.parentProjectLocalID == nil || resolvedParentID != nil else {
            return // The new parent hasn't synced yet — retry this item on a later pass.
        }
        if let baseUpdatedAt = payload.baseUpdatedAt, let serverUpdatedAt = currentRow.serverUpdatedAt,
           serverUpdatedAt > baseUpdatedAt {
            try await flagConflict(item)
            return
        }
        let project = Project(
            id: .remote(remoteID),
            title: payload.title,
            description: payload.description,
            isArchived: payload.isArchived,
            isFavorite: payload.isFavorite,
            parentProjectID: resolvedParentID.map(EntityID.remote),
            position: payload.position,
            hexColor: payload.hexColor,
        )
        let updated = try await projectRepository.update(project)
        try await applyPushResult(updated, deleting: item)
    }

    private func drainDelete(_ item: MutationQueueRecord) async throws {
        guard let payload: ProjectDeletePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        try await projectRepository.delete(id: .remote(payload.remoteID))
        try await localStore.write { db in
            if let row = try ProjectRecord.fetchOne(db, key: item.targetLocalID) {
                try row.delete(db)
            }
            try item.delete(db)
        }
    }

    /// Persists a successful `create`/`update`'s server response and
    /// removes the drained queue item. Shared because the two operations'
    /// post-success bookkeeping is otherwise identical — `create` is simply
    /// the case where `remoteID` was `nil` beforehand.
    private func applyPushResult(_ project: Project, deleting item: MutationQueueRecord) async throws {
        guard let remoteID = project.id.remoteValue else {
            preconditionFailure("SyncEngine: a pushed create/update's response must carry a resolved remote id")
        }
        try await localStore.write { db in
            if var row = try ProjectRecord.fetchOne(db, key: item.targetLocalID) {
                row.remoteID = remoteID
                row.serverUpdatedAt = project.updated
                try row.save(db)
            }
            try item.delete(db)
        }
    }

    private func flagConflict(_ item: MutationQueueRecord) async throws {
        try await localStore.write { db in
            var row = item
            row.needsConflictResolution = true
            try row.update(db)
        }
    }

    private func markFailed(_ item: MutationQueueRecord, error: Error) async {
        try? await localStore.write { db in
            var row = item
            row.retryCount += 1
            row.lastError = String(describing: error)
            row.status = .failed
            try row.update(db)
        }
    }

    private static func resolveRemoteID(forLocalID localID: UUID?, db: Database) throws -> Int? {
        guard let localID else { return nil }
        return try ProjectRecord.fetchOne(db, key: localID)?.remoteID
    }

    private func decodePayload<T: Decodable>(_ payload: String?) throws -> T? {
        guard let payload, let data = payload.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
