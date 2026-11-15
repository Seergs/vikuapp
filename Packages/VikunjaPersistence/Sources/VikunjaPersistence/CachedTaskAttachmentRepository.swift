import Foundation
import GRDB
import VikunjaCore

/// Persists attachment metadata only. Uploads, deletions and file downloads
/// still require the server; no file bytes enter the local database.
public struct CachedTaskAttachmentRepository: TaskAttachmentRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let remote: any TaskAttachmentRepositoryProtocol
    private let reachability: (any ReachabilityMonitoring)?

    public init(
        localStore: LocalStore, accountID: UUID, remote: any TaskAttachmentRepositoryProtocol,
        reachability: (any ReachabilityMonitoring)? = nil,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.remote = remote
        self.reachability = reachability
    }

    public func cachedAttachmentSnapshot(taskID: Int) async throws -> TaskAttachmentSnapshot? {
        try await localStore.read { db in
            guard let task = try findTask(taskID: taskID, db: db),
                  let catalog = try catalog(taskLocalID: task.localID, db: db) else { return nil }
            let attachments = try records(taskLocalID: task.localID).order(Column("position")).fetchAll(db)
                .map { $0.attachment(taskID: taskID) }
            guard catalog.lastSuccessfulDownloadAt != nil || !attachments.isEmpty else { return nil }
            return TaskAttachmentSnapshot(
                attachments: attachments, lastSuccessfulDownloadAt: catalog.lastSuccessfulDownloadAt,
            )
        }
    }

    public func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        try await requireConnection()
        let request = try await beginRequest(taskID: taskID)
        let attachments = try await remote.fetchAttachments(taskID: taskID)
        try Task.checkCancellation()
        try await localStore.write { db in
            guard var current = try catalog(taskLocalID: request.taskLocalID, db: db),
                  current.revision == request.revision else { throw CancellationError() }
            try records(taskLocalID: request.taskLocalID).deleteAll(db)
            for (position, attachment) in attachments.enumerated() {
                try TaskAttachmentRecord(
                    attachment: attachment, accountID: accountID,
                    taskLocalID: request.taskLocalID, position: position,
                ).insert(db)
            }
            current.lastSuccessfulDownloadAt = Date()
            try current.update(db)
        }
        return attachments
    }

    public func uploadAttachment(
        data: Data, fileName: String, mimeType: String, toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        try await requireConnection()
        let request = try await beginRequest(taskID: taskID)
        let created = try await remote.uploadAttachment(
            data: data, fileName: fileName, mimeType: mimeType, toTask: taskID,
        )
        await reconcileConfirmedWrite { db in
            // A deleted task or replaced account cache must stay deleted.
            guard var current = try catalog(taskLocalID: request.taskLocalID, db: db) else { return }
            current.revision = UUID()
            try current.update(db)
            let existing = try records(taskLocalID: request.taskLocalID).fetchAll(db)
            var position = (existing.map(\.position).max() ?? -1) + 1
            for attachment in created {
                let previous = existing.first { $0.remoteID == attachment.id }
                try TaskAttachmentRecord(
                    attachment: attachment, accountID: accountID, taskLocalID: request.taskLocalID,
                    position: previous?.position ?? position,
                ).save(db)
                position += 1
            }
        }
        return created
    }

    public func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        try await requireConnection()
        let request = try await beginRequest(taskID: taskID)
        try await remote.deleteAttachment(id, fromTask: taskID)
        await reconcileConfirmedWrite { db in
            guard var current = try catalog(taskLocalID: request.taskLocalID, db: db) else { return }
            current.revision = UUID()
            try current.update(db)
            try records(taskLocalID: request.taskLocalID).filter(Column("remoteID") == id).deleteAll(db)
        }
    }

    public func downloadAttachment(
        _ id: Int, fromTask taskID: Int, previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        try await requireConnection()
        return try await remote.downloadAttachment(id, fromTask: taskID, previewSize: previewSize)
    }

    private func requireConnection() async throws {
        try Task.checkCancellation()
        if await reachability?.isKnownOffline == true {
            throw VikunjaError.offline
        }
    }

    /// A confirmed server mutation stays successful if its caller is cancelled
    /// or account recovery rejects the cache update. Await this small transaction
    /// independently of caller cancellation; the database execution lifecycle still
    /// controls suspension. A rejected cache update is repaired by the next refresh.
    private func reconcileConfirmedWrite(_ updates: @escaping @Sendable (Database) throws -> Void) async {
        _ = try? await Task { try await localStore.write(updates) }.value
    }

    /// Invalidates older reads before every request. Successful writes invalidate
    /// reads again, including those started while the write was in flight.
    private func beginRequest(taskID: Int) async throws -> TaskAttachmentCatalogRecord {
        try await localStore.write { db in
            guard let task = try findTask(taskID: taskID, db: db) else { throw VikunjaError.notFound }
            var current = try catalog(taskLocalID: task.localID, db: db) ?? TaskAttachmentCatalogRecord(
                accountID: accountID, taskLocalID: task.localID, revision: UUID(), lastSuccessfulDownloadAt: nil,
            )
            current.revision = UUID()
            try current.save(db)
            return current
        }
    }

    private func findTask(taskID: Int, db: Database) throws -> TaskRecord? {
        try TaskRecord.filter(Column("accountID") == accountID && Column("remoteID") == taskID).fetchOne(db)
    }

    private func catalog(taskLocalID: UUID, db: Database) throws -> TaskAttachmentCatalogRecord? {
        try TaskAttachmentCatalogRecord
            .filter(Column("accountID") == accountID && Column("taskLocalID") == taskLocalID).fetchOne(db)
    }

    private func records(taskLocalID: UUID) -> QueryInterfaceRequest<TaskAttachmentRecord> {
        TaskAttachmentRecord.filter(Column("accountID") == accountID && Column("taskLocalID") == taskLocalID)
    }
}
