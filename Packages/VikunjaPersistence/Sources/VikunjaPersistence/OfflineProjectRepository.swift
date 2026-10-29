import Foundation
import GRDB
import VikunjaCore

/// Local-first `ProjectRepositoryProtocol`: every read serves the local
/// cache, and every write lands locally first (so the caller sees it
/// immediately, online or not) and queues a mutation to replay against the
/// server. `syncEngine` is this same account's own engine, reused here
/// purely to drain that queue right after a write, if the network happens
/// to be up already - the third of the four sync triggers, the other three
/// (foreground, reachability regained, background refresh) living outside
/// this type entirely.
public actor OfflineProjectRepository: ProjectRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncEngine: SyncEngine
    private let reachability: ReachabilityMonitoring

    public init(localStore: LocalStore, accountID: UUID, syncEngine: SyncEngine, reachability: ReachabilityMonitoring) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncEngine = syncEngine
        self.reachability = reachability
    }

    public func fetchProjects() async throws -> [Project] {
        await pullIfNeverSynced()
        return try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            let rowsByLocalID = Dictionary(uniqueKeysWithValues: rows.map { ($0.localID, $0) })
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) }
                .map { Self.project(from: $0, rowsByLocalID: rowsByLocalID) }
        }
    }

    public func fetchProject(id: EntityID) async throws -> Project {
        await pullIfNeverSynced()
        return try await readProject(id: id)
    }

    /// The actual local read behind `fetchProject(id:)`, without the
    /// cold-pull trigger — `create`/`update` call this instead of the public
    /// method to read back the row they just wrote, since a pull running in
    /// between could reconcile-delete that same row before the server's own
    /// response has caught up to it (nothing queued to protect it anymore,
    /// since the drain that just ran already cleared the queue item).
    private func readProject(id: EntityID) async throws -> Project {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            guard !hiddenLocalIDs.contains(row.localID) else { throw VikunjaError.notFound }
            let rowsByLocalID = Dictionary(uniqueKeysWithValues: rows.map { ($0.localID, $0) })
            return Self.project(from: row, rowsByLocalID: rowsByLocalID)
        }
    }

    public func create(_ project: Project) async throws -> Project {
        let localID = UUID()
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            let parentLocalID = project.parentProjectID.flatMap { Self.resolveLocalID(matching: $0, in: rows) }
            try ProjectRecord(
                localID: localID,
                accountID: self.accountID,
                remoteID: nil,
                title: project.title,
                description: project.description,
                isArchived: project.isArchived,
                isFavorite: project.isFavorite,
                parentProjectLocalID: parentLocalID,
                position: project.position,
                hexColor: project.hexColor,
                serverUpdatedAt: nil,
            ).insert(db)
            let payload = ProjectCreateOrUpdatePayload(
                title: project.title,
                description: project.description,
                isArchived: project.isArchived,
                isFavorite: project.isFavorite,
                parentProjectLocalID: parentLocalID,
                position: project.position,
                hexColor: project.hexColor,
                baseUpdatedAt: nil,
            )
            try Self.enqueueOrCoalesce(context: EnqueueContext(
                operation: .create,
                targetLocalID: localID,
                accountID: self.accountID,
                payload: payload,
                baseUpdatedAt: nil,
            ), db: db)
        }
        await triggerDrainIfOnline()
        return try await readProject(id: .local(localID))
    }

    public func update(_ project: Project) async throws -> Project {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard var row = Self.findRow(matching: project.id, in: rows) else { throw VikunjaError.notFound }
            let parentLocalID = project.parentProjectID.flatMap { Self.resolveLocalID(matching: $0, in: rows) }
            row.title = project.title
            row.description = project.description
            row.isArchived = project.isArchived
            row.isFavorite = project.isFavorite
            row.parentProjectLocalID = parentLocalID
            row.position = project.position
            row.hexColor = project.hexColor
            try row.save(db)

            let payload = ProjectCreateOrUpdatePayload(
                title: project.title,
                description: project.description,
                isArchived: project.isArchived,
                isFavorite: project.isFavorite,
                parentProjectLocalID: parentLocalID,
                position: project.position,
                hexColor: project.hexColor,
                baseUpdatedAt: row.serverUpdatedAt,
            )
            // A row that's never synced still has its original `create`
            // pending - that's the mutation this edit must update in place,
            // since `drainUpdate` bails out on a row with no `remoteID` yet.
            let operation: MutationOperation = row.remoteID == nil ? .create : .update
            try Self.enqueueOrCoalesce(context: EnqueueContext(
                operation: operation,
                targetLocalID: row.localID,
                accountID: self.accountID,
                payload: payload,
                baseUpdatedAt: row.serverUpdatedAt,
            ), db: db)
        }
        await triggerDrainIfOnline()
        return try await readProject(id: project.id)
    }

    public func delete(id: EntityID) async throws {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }

            // Any other mutation still pending (or failed but retryable)
            // against this row is moot once it's being deleted.
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.targetLocalID == row.localID
                        && ($0.status == .pending || $0.status == .failed)
                }
                .forEach { try $0.delete(db) }

            guard let remoteID = row.remoteID else {
                // Never synced - nothing server-side to delete.
                try row.delete(db)
                return
            }
            let payload = ProjectDeletePayload(remoteID: remoteID)
            var item = try MutationQueueRecord(
                id: nil,
                accountID: self.accountID,
                entityType: .project,
                operation: .delete,
                targetLocalID: row.localID,
                payload: Self.encode(payload),
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
        await triggerDrainIfOnline()
    }

    private func triggerDrainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainProjectMutations()
    }

    /// Blocks the very first read against an account's cache on a cold pull
    /// — otherwise a screen that reads before `SyncCoordinator`'s own
    /// background pull has landed would see an empty cache with nothing to
    /// ever tell it to refresh, since nothing here observes the local store
    /// for later changes. Every later read, once a pull has happened at
    /// least once, serves the cache as-is and leaves staleness to the other
    /// triggers, exactly as intended.
    private func pullIfNeverSynced() async {
        let alreadyPulled = await (try? localStore.read { db in
            try SyncStateRecord.fetchAll(db).contains { $0.accountID == self.accountID && $0.entityType == .project }
        }) ?? false
        guard !alreadyPulled, await reachability.isReachable else { return }
        try? await syncEngine.pullProjects()
    }

    private static func accountRows(_ accountID: UUID, db: Database) throws -> [ProjectRecord] {
        try ProjectRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    /// Target ids to hide from a read — a delete the user asked for stays
    /// hidden whether it's still pending its first attempt or failed and
    /// waiting to be retried; either way it's not coming back.
    private static func pendingDeleteTargetLocalIDs(accountID: UUID, db: Database) throws -> Set<UUID> {
        try Set(
            MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == accountID
                        && ($0.entityType == .project || $0.entityType == .filter)
                        && $0.operation == .delete
                        && ($0.status == .pending || $0.status == .failed)
                }
                .map(\.targetLocalID),
        )
    }

    private static func findRow(matching id: EntityID, in rows: [ProjectRecord]) -> ProjectRecord? {
        switch id {
        case let .local(localID): rows.first { $0.localID == localID }
        case let .remote(remoteID): rows.first { $0.remoteID == remoteID }
        }
    }

    private static func resolveLocalID(matching id: EntityID, in rows: [ProjectRecord]) -> UUID? {
        switch id {
        case let .local(localID): localID
        case let .remote(remoteID): rows.first { $0.remoteID == remoteID }?.localID
        }
    }

    private static func project(from row: ProjectRecord, rowsByLocalID: [UUID: ProjectRecord]) -> Project {
        let parentID = row.parentProjectLocalID.flatMap { rowsByLocalID[$0] }
            .map { $0.remoteID.map(EntityID.remote) ?? .local($0.localID) }
        return Project(
            id: row.remoteID.map(EntityID.remote) ?? .local(row.localID),
            title: row.title,
            description: row.description,
            isArchived: row.isArchived,
            isFavorite: row.isFavorite,
            parentProjectID: parentID,
            position: row.position,
            hexColor: row.hexColor,
            updated: row.serverUpdatedAt,
        )
    }

    /**
     Replaces an existing pending (or failed and still retryable) mutation
     of the same `operation` against `targetLocalID` in place (preserving
     its original `createdAt`, so several quick edits still drain in their
     original queue position) rather than stacking up one queue row per
     edit. Resets a coalesced-into `.failed` item back to `.pending` —
     this is a fresh edit with its own fresh payload, not a retry of the
     one that failed.
     */
    private struct EnqueueContext {
        let operation: MutationOperation
        let targetLocalID: UUID
        let accountID: UUID
        let payload: any Encodable
        let baseUpdatedAt: Date?
    }

    private static func enqueueOrCoalesce(context: EnqueueContext, db: Database) throws {
        let encoded = try Self.encode(context.payload)
        let existing = try MutationQueueRecord.fetchAll(db).first {
            $0.accountID == context.accountID && $0.entityType == .project && $0.targetLocalID == context.targetLocalID
                && ($0.status == .pending || $0.status == .failed) && $0.operation == context.operation
        }
        if var existing {
            existing.payload = encoded
            existing.status = .pending
            existing.needsConflictResolution = false
            existing.baseUpdatedAt = context.baseUpdatedAt
            try existing.update(db)
        } else {
            var item = MutationQueueRecord(
                id: nil,
                accountID: context.accountID,
                entityType: .project,
                operation: context.operation,
                targetLocalID: context.targetLocalID,
                payload: encoded,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
                baseUpdatedAt: context.baseUpdatedAt,
            )
            try item.insert(db)
        }
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
