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
                  let project = try ProjectRecord.fetchOne(db, key: payload.projectLocalID), !project.isArchived
            else { throw VikunjaError.notFound }
            let titles = try KanbanViewCatalogRecord.fetchOne(db, key: project.localID)?.views ?? []
            return try Self.recoveryViews(project.localID, original: destination.viewID, db: db).flatMap { view in
                let title = titles.first { $0.id == view.remoteID }?.title
                return try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                    .order(Column("position"), Column("remoteID")).fetchAll(db).map { bucket in
                        let label = if view.remoteID != destination.viewID, let title, !title.isEmpty {
                            "\(title) · \(bucket.title)"
                        } else {
                            bucket.title
                        }
                        let available: Bool
                        do {
                            try KanbanCapacity.check(bucket, excluding: item.targetLocalID, db: db)
                            available = true
                        } catch let error as VikunjaError where error.isBucketCapacityError {
                            available = false
                        }
                        return KanbanCreationBucket(id: bucket.remoteID, title: label, isFull: !available)
                    }
            }
        }
    }

    public func retryCreation(operationID: Int64, bucketID: Int?) async throws {
        try await localStore.write { db in
            var (item, payload) = try rejectedCreation(operationID, db: db)
            guard var destination = payload.kanbanDestination,
                  var task = try TaskRecord.fetchOne(db, key: item.targetLocalID), task.remoteID == nil,
                  let project = try ProjectRecord.fetchOne(db, key: task.projectLocalID), !project.isArchived
            else { throw VikunjaError.notFound }
            let views = try Self.recoveryViews(project.localID, original: destination.viewID, db: db)
            let eligible = views.filter { bucketID != nil || $0.remoteID == destination.viewID }
            guard let bucket = try KanbanBucketRecord.filter(eligible.map(\.localID).contains(Column("viewLocalID")))
                .filter(Column("remoteID") == (bucketID ?? destination.bucketID)).fetchOne(db),
                let view = eligible.first(where: { $0.localID == bucket.viewLocalID })
            else { throw VikunjaError.notFound }
            try KanbanCapacity.check(bucket, excluding: task.localID, db: db)
            if destination.bucketID != bucket.remoteID {
                if bucket.remoteID == view.doneBucketID {
                    task.isDone = true
                } else if destination.viewID == view.remoteID, destination.bucketID == view.doneBucketID {
                    task.isDone = false
                }
            }
            destination.viewID = view.remoteID
            destination.bucketID = bucket.remoteID
            payload.kanbanDestination = destination
            payload.kanbanCreatedOnline = false // Explicit recovery must keep the user's work on another rejection.
            payload.isDone = task.isDone
            item.payload = try KanbanLocalMutations.encode(payload)
            item.status = .pending
            item.needsConflictResolution = false
            item.lastError = nil
            item.failureDetails = nil
            item.retryCount = 0
            try item.update(db)
            try task.update(db)
            try KanbanLocalMutations.place(task, in: bucket, db: db)
        }
        await syncRequester.requestSync()
    }

    private static func recoveryViews(_ projectID: UUID, original: Int, db: Database) throws -> [KanbanViewRecord] {
        let views = try KanbanViewRecord.filter(Column("projectLocalID") == projectID)
            .order(Column("remoteID")).fetchAll(db).filter(KanbanLocalMutations.supports)
        if let current = views.first(where: { $0.remoteID == original }) {
            return [current]
        }
        return views
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
