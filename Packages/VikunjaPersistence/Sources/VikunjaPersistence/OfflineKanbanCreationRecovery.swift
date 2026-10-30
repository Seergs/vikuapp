import Foundation
import GRDB
import VikunjaCore

/// Account-bound recovery; no network request is needed to preserve or redirect local work.
public struct OfflineKanbanCreationRecovery: KanbanCreationRecovering {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncRequester: SyncRequesting

    public init(localStore: LocalStore, accountID: UUID, syncRequester: SyncRequesting) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
    }

    public func recoveryBuckets(operationID: Int64) async throws -> [KanbanCreationBucket] {
        try await localStore.read { db in
            let (item, payload) = try rejectedCreation(operationID, db: db)
            guard let destination = payload.kanbanDestination,
                  let view = try KanbanViewRecord.filter(Column("projectLocalID") == payload.projectLocalID)
                  .filter(Column("remoteID") == destination.viewID).fetchOne(db), KanbanLocalMutations.supports(view),
                  let project = try ProjectRecord.fetchOne(db, key: payload.projectLocalID), !project.isArchived
            else { throw VikunjaError.notFound }
            // Use the same snapshot as the board, removing this task's reserved slot.
            return try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                .order(Column("position"), Column("remoteID")).fetchAll(db).map { bucket in
                    let available: Bool
                    do {
                        try KanbanCapacity.check(bucket, excluding: item.targetLocalID, db: db)
                        available = true
                    } catch VikunjaError.bucketFull {
                        available = false
                    }
                    return KanbanCreationBucket(id: bucket.remoteID, title: bucket.title, isFull: !available)
                }
        }
    }

    public func retryCreation(operationID: Int64, bucketID: Int?) async throws {
        try await localStore.write { db in
            var (item, payload) = try rejectedCreation(operationID, db: db)
            guard var destination = payload.kanbanDestination,
                  var task = try TaskRecord.fetchOne(db, key: item.targetLocalID), task.remoteID == nil,
                  let project = try ProjectRecord.fetchOne(db, key: task.projectLocalID), !project.isArchived,
                  let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
                  .filter(Column("remoteID") == destination.viewID).fetchOne(db), KanbanLocalMutations.supports(view),
                  let bucket = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                  .filter(Column("remoteID") == (bucketID ?? destination.bucketID)).fetchOne(db)
            else { throw VikunjaError.notFound }
            try KanbanCapacity.check(bucket, excluding: task.localID, db: db)
            if destination.bucketID != bucket.remoteID {
                if bucket.remoteID == view.doneBucketID {
                    task.isDone = true
                } else if destination.bucketID == view.doneBucketID {
                    task.isDone = false
                }
            }
            destination.bucketID = bucket.remoteID
            payload.kanbanDestination = destination
            payload.kanbanCreatedOnline = false // Explicit recovery must keep the user's work on another rejection.
            payload.isDone = task.isDone
            item.payload = try KanbanLocalMutations.encode(payload)
            item.status = .pending
            item.needsConflictResolution = false
            item.lastError = nil
            item.retryCount = 0
            try item.update(db)
            try task.update(db)
            try KanbanAssignmentRecord(
                accountID: accountID, projectLocalID: project.localID, viewLocalID: view.localID,
                bucketLocalID: bucket.localID, taskLocalID: task.localID,
                position: KanbanLocalMutations.nextPosition(bucket.localID, db: db),
            ).save(db)
        }
        await syncRequester.requestSync()
    }

    public func deleteRejectedCreation(operationID: Int64) async throws {
        try await localStore.write { db in
            let (item, _) = try rejectedCreation(operationID, db: db)
            try RejectedLocalTaskRemoval.remove(item.targetLocalID, accountID: accountID, db: db)
        }
    }

    private func rejectedCreation(_ id: Int64, db: Database) throws -> (MutationQueueRecord, TaskCreateOrUpdatePayload) {
        guard let item = try MutationQueueRecord.fetchOne(db, key: id), item.accountID == accountID,
              item.entityType == .task, item.operation == .create, item.status == .failed,
              item.needsConflictResolution,
              item.lastError.flatMap(KanbanCreationFailure.init(rawValue:))?.allowsRecovery == true,
              let task = try TaskRecord.fetchOne(db, key: item.targetLocalID), task.remoteID == nil,
              task.accountID == accountID
        else { throw VikunjaError.notFound }
        return try (item, KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: item))
    }
}

enum RejectedLocalTaskRemoval {
    /// A confirmed rejection has no remote task to delete. Remove its dependent queue entries too.
    static func remove(_ localID: UUID, accountID: UUID, db: Database) throws {
        let task = try TaskRecord.fetchOne(db, key: localID)
        guard task?.remoteID == nil, task == nil || task?.accountID == accountID else { return }
        let comments = try Set(TaskCommentRecord.filter(Column("taskLocalID") == localID).fetchAll(db).map(\.localID))
        for item in try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db) {
            let isRelation = item.entityType == .task && [.addRelation, .removeRelation].contains(item.operation)
            let refersToTask: Bool = if isRelation {
                try KanbanLocalMutations.decode(TaskRelationMutationPayload.self, item: item)
                    .otherTaskLocalID == localID
            } else {
                false
            }
            if item.targetLocalID == localID || comments.contains(item.targetLocalID) || refersToTask {
                try item.delete(db)
            }
        }
        try task?.delete(db) // Foreign keys cascade assignments, comments, relations and reminders.
    }
}
