import Foundation
import GRDB
import VikunjaCore

/// Local-first `TaskRepositoryProtocol` — same shape as
/// `OfflineProjectRepository`, minus the hierarchy machinery projects need
/// (a task has no children of its own), but keeping project's conflict-
/// detection machinery, unlike `OfflineLabelRepository`: Vikunja's task API
/// exposes `updated`, so `drainTaskUpdate` has a real baseline to compare a
/// queued edit against.
public actor OfflineTaskRepository: TaskRepositoryProtocol {
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

    public func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        await pullIfNeverSynced()
        return try await localStore.read { db in
            let projectRows = try Self.projectRows(self.accountID, db: db)
            guard let projectLocalID = projectRows.first(where: { $0.remoteID == projectID })?.localID else {
                return []
            }
            let rows = try Self.accountRows(self.accountID, db: db).filter { $0.projectLocalID == projectLocalID }
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            let projectsByLocalID = Self.projectsByLocalID(projectRows)
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) }
                .map { Self.task(from: $0, projectsByLocalID: projectsByLocalID) }
        }
    }

    public func fetchTask(id: EntityID) async throws -> VikunjaTask {
        await pullIfNeverSynced()
        return try await readTask(id: id)
    }

    /// The actual local read behind `fetchTask(id:)`, without the cold-pull
    /// trigger — `create`/`update` call this instead of the public method
    /// to read back the row they just wrote, since a pull running in
    /// between could reconcile-delete that same row before the server's own
    /// response has caught up to it (mirrors `OfflineProjectRepository.readProject`).
    private func readTask(id: EntityID) async throws -> VikunjaTask {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            guard !hiddenLocalIDs.contains(row.localID) else { throw VikunjaError.notFound }
            let projectsByLocalID = try Self.projectsByLocalID(Self.projectRows(self.accountID, db: db))
            return Self.task(from: row, projectsByLocalID: projectsByLocalID)
        }
    }

    public func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        let localID = UUID()
        try await localStore.write { db in
            let projectRows = try Self.projectRows(self.accountID, db: db)
            guard let projectLocalID = Self.resolveProjectLocalID(matching: task.projectID, in: projectRows) else {
                throw VikunjaError.notFound
            }
            try TaskRecord(
                localID: localID,
                accountID: self.accountID,
                remoteID: nil,
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                serverUpdatedAt: nil,
            ).insert(db)
            let payload = TaskCreateOrUpdatePayload(
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                baseUpdatedAt: nil,
            )
            try Self.enqueueOrCoalesce(
                operation: .create, targetLocalID: localID, accountID: self.accountID, payload: payload, db: db,
            )
        }
        await triggerDrainIfOnline()
        return try await readTask(id: .local(localID))
    }

    public func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard var row = Self.findRow(matching: task.id, in: rows) else { throw VikunjaError.notFound }
            let projectRows = try Self.projectRows(self.accountID, db: db)
            guard let projectLocalID = Self.resolveProjectLocalID(matching: task.projectID, in: projectRows) else {
                throw VikunjaError.notFound
            }
            row.title = task.title
            row.description = task.description
            row.isDone = task.isDone
            row.dueDate = task.dueDate
            row.priority = task.priority.rawValue
            row.projectLocalID = projectLocalID
            try row.save(db)

            let payload = TaskCreateOrUpdatePayload(
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                baseUpdatedAt: row.serverUpdatedAt,
            )
            // A row that's never synced still has its original `create`
            // pending - that's the mutation this edit must update in place,
            // since `drainTaskUpdate` bails out on a row with no `remoteID` yet.
            let operation: MutationOperation = row.remoteID == nil ? .create : .update
            try Self.enqueueOrCoalesce(
                operation: operation, targetLocalID: row.localID, accountID: self.accountID, payload: payload, db: db,
            )
        }
        await triggerDrainIfOnline()
        return try await readTask(id: task.id)
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
            let payload = TaskDeletePayload(remoteID: remoteID)
            var item = try MutationQueueRecord(
                id: nil,
                accountID: self.accountID,
                entityType: .task,
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

    public func searchTasks(query: String) async throws -> [VikunjaTask] {
        await pullIfNeverSynced()
        return try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            let projectsByLocalID = try Self.projectsByLocalID(Self.projectRows(self.accountID, db: db))
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) && $0.title.localizedCaseInsensitiveContains(query) }
                .map { Self.task(from: $0, projectsByLocalID: projectsByLocalID) }
        }
    }

    private func triggerDrainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainTaskMutations()
    }

    /// Blocks the very first read against an account's cache on a cold pull
    /// — see `OfflineProjectRepository.pullIfNeverSynced` for the full
    /// rationale (identical reasoning, one per entity).
    private func pullIfNeverSynced() async {
        let alreadyPulled = await (try? localStore.read { db in
            try SyncStateRecord.fetchAll(db).contains { $0.accountID == self.accountID && $0.entityType == .task }
        }) ?? false
        guard !alreadyPulled, await reachability.isReachable else { return }
        try? await syncEngine.pullTasks()
    }

    private static func accountRows(_ accountID: UUID, db: Database) throws -> [TaskRecord] {
        try TaskRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    private static func projectRows(_ accountID: UUID, db: Database) throws -> [ProjectRecord] {
        try ProjectRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    private static func projectsByLocalID(_ projectRows: [ProjectRecord]) -> [UUID: ProjectRecord] {
        Dictionary(uniqueKeysWithValues: projectRows.map { ($0.localID, $0) })
    }

    /// Target ids to hide from a read — a delete the user asked for stays
    /// hidden whether it's still pending its first attempt or failed and
    /// waiting to be retried; either way it's not coming back.
    private static func pendingDeleteTargetLocalIDs(accountID: UUID, db: Database) throws -> Set<UUID> {
        try Set(
            MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == accountID && $0.entityType == .task && $0.operation == .delete
                        && ($0.status == .pending || $0.status == .failed)
                }
                .map(\.targetLocalID),
        )
    }

    private static func findRow(matching id: EntityID, in rows: [TaskRecord]) -> TaskRecord? {
        switch id {
        case let .local(localID): rows.first { $0.localID == localID }
        case let .remote(remoteID): rows.first { $0.remoteID == remoteID }
        }
    }

    /// Resolves the task's project reference to a local id — the same
    /// `.local`/`.remote` switch `OfflineProjectRepository.resolveLocalID`
    /// uses for a sub-project's parent, just reading `project` rows instead
    /// of this actor's own table. `nil` means the project genuinely isn't
    /// known locally yet (a real ordering bug upstream, since a task's
    /// project is never optional), not just "not synced" — `.local` is
    /// checked against real rows too, not trusted blindly.
    private static func resolveProjectLocalID(matching id: EntityID, in projectRows: [ProjectRecord]) -> UUID? {
        switch id {
        case let .local(localID): projectRows.contains { $0.localID == localID } ? localID : nil
        case let .remote(remoteID): projectRows.first { $0.remoteID == remoteID }?.localID
        }
    }

    private static func task(from row: TaskRecord, projectsByLocalID: [UUID: ProjectRecord]) -> VikunjaTask {
        let projectID = projectsByLocalID[row.projectLocalID]?.remoteID.map(EntityID.remote)
            ?? .local(row.projectLocalID)
        return VikunjaTask(
            id: row.remoteID.map(EntityID.remote) ?? .local(row.localID),
            title: row.title,
            description: row.description,
            isDone: row.isDone,
            dueDate: row.dueDate,
            priority: VikunjaTask.Priority(rawValue: row.priority) ?? .unset,
            projectID: projectID,
            updated: row.serverUpdatedAt,
        )
    }

    /// Replaces an existing pending (or failed and still retryable) mutation
    /// of the same `operation` against `targetLocalID` in place — see
    /// `OfflineProjectRepository.enqueueOrCoalesce`'s doc comment for the
    /// full rationale (identical reasoning, one per entity).
    private static func enqueueOrCoalesce(
        operation: MutationOperation,
        targetLocalID: UUID,
        accountID: UUID,
        payload: some Encodable,
        db: Database,
    ) throws {
        let encoded = try Self.encode(payload)
        let existing = try MutationQueueRecord.fetchAll(db).first {
            $0.accountID == accountID && $0.entityType == .task && $0.targetLocalID == targetLocalID
                && ($0.status == .pending || $0.status == .failed) && $0.operation == operation
        }
        if var existing {
            existing.payload = encoded
            existing.status = .pending
            existing.needsConflictResolution = false
            try existing.update(db)
        } else {
            var item = MutationQueueRecord(
                id: nil,
                accountID: accountID,
                entityType: .task,
                operation: operation,
                targetLocalID: targetLocalID,
                payload: encoded,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
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
