import Foundation
import GRDB
import VikunjaCore

/// Local-first `TaskCommentRepositoryProtocol` — comments are the last task
/// sub-resource Slice 4 brings offline (attachments stay online-only by
/// design). Reading is always from the local cache; a reachable network only
/// refreshes that cache first. Writes are applied locally immediately and
/// queued as their own `.comment` mutations, which
/// `SyncEngine.drainCommentMutations()` replays once the task itself has a
/// remote id.
public actor OfflineTaskCommentRepository: TaskCommentRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncEngine: SyncEngine
    private let reachability: ReachabilityMonitoring
    /// The signed-in user, used only as the author on a comment created
    /// offline — the server replaces it with the real one when the queued
    /// create drains. Optional because the app may not have cached a current
    /// user yet (e.g. first launch with no connection).
    private let currentUser: User?

    public init(
        localStore: LocalStore,
        accountID: UUID,
        syncEngine: SyncEngine,
        reachability: ReachabilityMonitoring,
        currentUser: User? = nil,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncEngine = syncEngine
        self.reachability = reachability
        self.currentUser = currentUser
    }

    public func fetchComments(taskID: EntityID) async throws -> [TaskComment] {
        let taskRow = try await localStore.read { db in
            try Self.findTaskRow(matching: taskID, accountID: self.accountID, db: db)
        }
        guard let taskRow else { throw VikunjaError.notFound }

        // A task that hasn't synced yet has no server-side comments to pull,
        // but it can still have locally queued ones. A reachable network is
        // a best-effort refresh: a pull failure falls back to the cache
        // below, so an offline-looking-but-reachable network never turns a
        // previously loaded thread into an error.
        if taskRow.remoteID != nil, await reachability.isReachable {
            try? await syncEngine.pullComments(taskID: .local(taskRow.localID))
        }
        return try await readComments(taskLocalID: taskRow.localID)
    }

    public func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment {
        let localID = UUID()
        let now = Date()
        let author = currentUser ?? User(id: 0, username: "")
        try await localStore.write { db in
            guard let taskRow = try Self.findTaskRow(matching: taskID, accountID: self.accountID, db: db) else {
                throw VikunjaError.notFound
            }
            try TaskCommentRecord(
                localID: localID,
                accountID: self.accountID,
                remoteID: nil,
                taskLocalID: taskRow.localID,
                comment: text,
                authorID: author.id,
                authorUsername: author.username,
                authorName: author.name,
                authorEmail: author.email,
                created: now,
                updated: now,
            ).insert(db)
            try Self.enqueue(
                operation: .create,
                targetLocalID: localID,
                accountID: self.accountID,
                payload: TaskCommentCreatePayload(taskLocalID: taskRow.localID, text: text),
                db: db,
            )
        }
        await triggerDrainIfOnline()
        return try await readComment(id: .local(localID))
    }

    public func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard var row = Self.findRow(matching: commentID, in: rows) else { throw VikunjaError.notFound }
            row.comment = text
            row.updated = Date()
            try row.save(db)

            if row.remoteID == nil {
                // The comment's original create is still queued (or failed but
                // retryable) — that is the mutation this edit has to update in
                // place, since a bare `update` can't address a server row yet.
                try Self.coalesce(
                    operation: .create,
                    targetLocalID: row.localID,
                    accountID: self.accountID,
                    payload: TaskCommentCreatePayload(taskLocalID: row.taskLocalID, text: text),
                    db: db,
                )
            } else {
                try Self.coalesce(
                    operation: .update,
                    targetLocalID: row.localID,
                    accountID: self.accountID,
                    payload: TaskCommentUpdatePayload(taskLocalID: row.taskLocalID, text: text),
                    db: db,
                )
            }
        }
        await triggerDrainIfOnline()
        return try await readComment(id: commentID)
    }

    public func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: commentID, in: rows) else { throw VikunjaError.notFound }

            // Any create/update still pending against this comment is moot
            // once it's being deleted.
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .comment
                        && $0.targetLocalID == row.localID
                        && ($0.status == .pending || $0.status == .failed)
                }
                .forEach { try $0.delete(db) }

            guard let remoteID = row.remoteID else {
                // Never synced — nothing server-side to delete.
                try row.delete(db)
                return
            }
            try row.delete(db)
            try Self.enqueue(
                operation: .delete,
                targetLocalID: row.localID,
                accountID: self.accountID,
                payload: TaskCommentDeletePayload(taskLocalID: row.taskLocalID, remoteID: remoteID),
                db: db,
            )
        }
        await triggerDrainIfOnline()
    }

    private func triggerDrainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainCommentMutations()
    }

    private func readComments(taskLocalID: UUID) async throws -> [TaskComment] {
        try await localStore.read { db in
            try Self.accountRows(self.accountID, db: db)
                .filter { $0.taskLocalID == taskLocalID }
                .sorted {
                    $0.created == $1.created ? $0.localID.uuidString < $1.localID.uuidString : $0.created < $1.created
                }
                .map(Self.comment(from:))
        }
    }

    private func readComment(id: EntityID) async throws -> TaskComment {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }
            return Self.comment(from: row)
        }
    }

    private static func accountRows(_ accountID: UUID, db: Database) throws -> [TaskCommentRecord] {
        try TaskCommentRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    private static func findTaskRow(matching id: EntityID, accountID: UUID, db: Database) throws -> TaskRecord? {
        let rows = try TaskRecord.fetchAll(db).filter { $0.accountID == accountID }
        switch id {
        case let .local(localID): return rows.first { $0.localID == localID }
        case let .remote(remoteID): return rows.first { $0.remoteID == remoteID }
        }
    }

    private static func findRow(matching id: EntityID, in rows: [TaskCommentRecord]) -> TaskCommentRecord? {
        switch id {
        case let .local(localID): rows.first { $0.localID == localID }
        case let .remote(remoteID): rows.first { $0.remoteID == remoteID }
        }
    }

    private static func comment(from row: TaskCommentRecord) -> TaskComment {
        TaskComment(
            id: row.remoteID.map(EntityID.remote) ?? .local(row.localID),
            comment: row.comment,
            author: User(
                id: row.authorID,
                username: row.authorUsername,
                name: row.authorName,
                email: row.authorEmail,
            ),
            created: row.created,
            updated: row.updated,
        )
    }

    private static func enqueue(
        operation: MutationOperation,
        targetLocalID: UUID,
        accountID: UUID,
        payload: some Encodable,
        db: Database,
    ) throws {
        var item = try MutationQueueRecord(
            id: nil,
            accountID: accountID,
            entityType: .comment,
            operation: operation,
            targetLocalID: targetLocalID,
            payload: Self.encode(payload),
            createdAt: Date(),
            retryCount: 0,
            lastError: nil,
            status: .pending,
            needsConflictResolution: false,
        )
        try item.insert(db)
    }

    private static func coalesce(
        operation: MutationOperation,
        targetLocalID: UUID,
        accountID: UUID,
        payload: some Encodable,
        db: Database,
    ) throws {
        let encoded = try Self.encode(payload)
        let existing = try MutationQueueRecord.fetchAll(db).first {
            $0.accountID == accountID && $0.entityType == .comment && $0.targetLocalID == targetLocalID
                && ($0.status == .pending || $0.status == .failed) && $0.operation == operation
        }
        if var existing {
            existing.payload = encoded
            existing.status = .pending
            existing.needsConflictResolution = false
            try existing.update(db)
        } else {
            try enqueue(
                operation: operation, targetLocalID: targetLocalID, accountID: accountID, payload: payload, db: db,
            )
        }
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
