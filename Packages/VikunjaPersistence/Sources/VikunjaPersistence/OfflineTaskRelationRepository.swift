import Foundation
import GRDB
import VikunjaCore

/// Local-first `TaskRelationRepositoryProtocol` — same shape as
/// `OfflineLabelRepository`'s `addLabel`/`removeLabel`: queues the mutation
/// against the *task* side (`entityType: .task`, same table
/// `drainTaskMutations()` already drains), resolved at drain time via
/// `TaskRelationMutationPayload.otherTaskLocalID`. Unlike a label attach,
/// *either* task referenced here can still be local-only, since a relation
/// can be created between two tasks both created offline in the same
/// session — the dependency-ordering wait applies to both sides, not just
/// one.
public actor OfflineTaskRelationRepository: TaskRelationRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncRequester: SyncRequesting

    public init(
        localStore: LocalStore,
        accountID: UUID,
        syncRequester: SyncRequesting,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
    }

    public func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws {
        try await enqueueTaskRelationMutation(.addRelation, kind: kind, otherTaskID: otherTaskID, taskID: taskID)
        await triggerDrainIfOnline()
    }

    public func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws {
        try await enqueueTaskRelationMutation(.removeRelation, kind: kind, otherTaskID: otherTaskID, taskID: taskID)
        await triggerDrainIfOnline()
    }

    private func enqueueTaskRelationMutation(
        _ operation: MutationOperation, kind: RelationKind, otherTaskID: EntityID, taskID: EntityID,
    ) async throws {
        try await localStore.write { db in
            guard let taskRow = try Self.findTaskRow(matching: taskID, accountID: self.accountID, db: db) else {
                throw VikunjaError.notFound
            }
            guard let otherTaskRow = try Self.findTaskRow(
                matching: otherTaskID, accountID: self.accountID, db: db,
            ) else {
                throw VikunjaError.notFound
            }
            let payload = TaskRelationMutationPayload(kind: kind, otherTaskLocalID: otherTaskRow.localID)
            var item = try MutationQueueRecord(
                id: nil,
                accountID: self.accountID,
                entityType: .task,
                operation: operation,
                targetLocalID: taskRow.localID,
                payload: Self.encode(payload),
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
    }

    private static func findTaskRow(matching id: EntityID, accountID: UUID, db: Database) throws -> TaskRecord? {
        let rows = try TaskRecord.fetchAll(db).filter { $0.accountID == accountID }
        switch id {
        case let .local(localID): return rows.first { $0.localID == localID }
        case let .remote(remoteID): return rows.first { $0.remoteID == remoteID }
        }
    }

    private func triggerDrainIfOnline() async {
        await syncRequester.requestSync()
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
