import Foundation
import GRDB
import VikunjaCore

/// Local-first project repository. Reads only query the account's database;
/// writes atomically persist local state and durable intent, then request the
/// shared account scheduler. No repository owns a network engine.
public actor OfflineProjectRepository: ProjectRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncRequester: SyncRequesting

    public init(localStore: LocalStore, accountID: UUID, syncRequester: SyncRequesting) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
    }

    public func fetchProjects() async throws -> [Project] {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            let hiddenLocalIDs = try ProjectSubtree.pendingDeleteIDs(accountID: self.accountID, rows: rows, db: db)
            let rowsByLocalID = Dictionary(uniqueKeysWithValues: rows.map { ($0.localID, $0) })
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) }
                .map { Self.project(from: $0, rowsByLocalID: rowsByLocalID) }
        }
    }

    public func fetchProject(id: EntityID) async throws -> Project {
        try await readProject(id: id)
    }

    private func readProject(id: EntityID) async throws -> Project {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }
            let hiddenLocalIDs = try ProjectSubtree.pendingDeleteIDs(accountID: self.accountID, rows: rows, db: db)
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

            let subtreeIDs = ProjectSubtree.localIDs(rootIDs: [row.localID], rows: rows)
            try ProjectSubtree.discardMutations(projectIDs: subtreeIDs, accountID: self.accountID, db: db)

            let remoteRoots = ProjectSubtree.remoteRoots(rootID: row.localID, rows: rows)
            let retainedIDs = ProjectSubtree.localIDs(rootIDs: Set(remoteRoots.map(\.localID)), rows: rows)
            for deletedRow in rows where subtreeIDs.contains(deletedRow.localID)
                && !retainedIDs.contains(deletedRow.localID) {
                try deletedRow.delete(db)
            }
            for root in remoteRoots {
                guard let remoteID = root.remoteID else { continue }
                var item = try MutationQueueRecord(
                    id: nil,
                    accountID: self.accountID,
                    entityType: .project,
                    operation: .delete,
                    targetLocalID: root.localID,
                    payload: Self.encode(ProjectDeletePayload(remoteID: remoteID)),
                    createdAt: Date(),
                    retryCount: 0,
                    lastError: nil,
                    status: .pending,
                    needsConflictResolution: false,
                )
                try item.insert(db)
            }
        }
        await triggerDrainIfOnline()
    }

    private func triggerDrainIfOnline() async {
        await syncRequester.requestSync()
    }

    private static func accountRows(_ accountID: UUID, db: Database) throws -> [ProjectRecord] {
        try ProjectRecord.fetchAll(db).filter { $0.accountID == accountID }
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
