import Foundation
import GRDB
import VikunjaCore

public struct OfflineKanbanBoardRepository: KanbanBoardRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncRequester: SyncRequesting

    public init(localStore: LocalStore, accountID: UUID, syncRequester: SyncRequesting) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
    }

    public func hasCachedKanbanSupport() async throws -> Bool {
        try await localStore.read { db in
            try KanbanViewRecord.filter(Column("accountID") == accountID)
                .filter(Column("lastCompletePullAt") != nil).fetchCount(db) > 0
        }
    }

    public func moveTask(
        taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int,
    ) async throws -> VikunjaTask {
        let (task, changed) = try await localStore.write { db in
            try KanbanLocalMutations.move(
                .init(taskID: taskID, projectID: projectID, viewID: viewID, bucketID: bucketID),
                accountID: accountID, db: db,
            )
        }
        if changed {
            await syncRequester.requestSync()
        }
        return task
    }

    public func createTask(
        title: String, projectID: EntityID, viewID: Int, bucketID: Int,
    ) async throws -> VikunjaTask {
        let created = try await localStore.write { db in
            let project = try ProjectRecord.filter(Column("accountID") == accountID).fetchAll(db).first {
                projectID == .local($0.localID) || $0.remoteID.map(EntityID.remote) == projectID
            }
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let project, let remoteID = project.remoteID, remoteID > 0, !project.isArchived,
                  let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
                  .filter(Column("remoteID") == viewID).fetchOne(db),
                  view.lastCompletePullAt != nil, view.mode == "manual",
                  view.filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let bucket = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                  .filter(Column("remoteID") == bucketID).fetchOne(db)
            else { throw VikunjaError.notFound }
            let localID = UUID()
            let done = view.doneBucketID == bucketID
            try TaskRecord(
                localID: localID,
                accountID: accountID,
                remoteID: nil,
                title: title,
                description: nil,
                isDone: done,
                dueDate: nil,
                priority: 0,
                projectLocalID: project.localID,
                serverUpdatedAt: nil,
            ).insert(db)
            let position = try KanbanAssignmentRecord.filter(Column("bucketLocalID") == bucket.localID)
                .fetchAll(db).map(\.position).max().map { $0 + 1 } ?? 0
            try KanbanAssignmentRecord(
                accountID: accountID,
                projectLocalID: project.localID,
                viewLocalID: view.localID,
                bucketLocalID: bucket.localID,
                taskLocalID: localID,
                position: position,
            ).insert(db)
            let payload = TaskCreateOrUpdatePayload(
                title: title,
                description: nil,
                isDone: done,
                dueDate: nil,
                priority: 0,
                projectLocalID: project.localID,
                baseUpdatedAt: nil,
                reminders: [],
                kanbanDestination: KanbanCreationDestination(viewID: viewID, bucketID: bucketID),
            )
            try Self.enqueueCreation(payload, localID: localID, accountID: accountID, db: db)
            return VikunjaTask(id: .local(localID), title: title, isDone: done, projectID: .remote(remoteID))
        }
        await syncRequester.requestSync()
        return created
    }

    private static func enqueueCreation(
        _ payload: TaskCreateOrUpdatePayload, localID: UUID, accountID: UUID, db: Database,
    ) throws {
        var mutation = try MutationQueueRecord(
            id: nil,
            accountID: accountID,
            entityType: .task,
            operation: .create,
            targetLocalID: localID,
            payload: String(data: JSONEncoder().encode(payload), encoding: .utf8),
            createdAt: Date(),
            retryCount: 0,
            lastError: nil,
            status: .pending,
            needsConflictResolution: false,
        )
        try mutation.insert(db)
    }

    public func fetchBoard(projectID: EntityID, viewID: Int?) async throws -> KanbanBoardSnapshot {
        try await localStore.read { db in
            let project = try ProjectRecord.filter(Column("accountID") == accountID).fetchAll(db).first {
                projectID == .local($0.localID) || $0.remoteID.map(EntityID.remote) == projectID
            }
            guard let project else { return .unavailable }
            guard project.remoteID != nil else { return .waitingForProject }
            guard let view = try KanbanViewRecord.filter(Column("accountID") == accountID)
                .filter(Column("projectLocalID") == project.localID)
                .order(Column("remoteID")).fetchAll(db).first(where: { viewID == nil || $0.remoteID == viewID }),
                let pulledAt = view.lastCompletePullAt
            else { return .unavailable }

            let records = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                .order(Column("position"), Column("remoteID")).fetchAll(db)
            let assignments = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
                .order(Column("position"), Column("taskLocalID")).fetchAll(db)
            let hidden = try Set(MutationQueueRecord.filter(Column("accountID") == accountID)
                .fetchAll(db).filter { $0.entityType == .task && $0.operation == .delete }.map(\.targetLocalID))
            let tasks = try TaskRecord.filter(Column("accountID") == accountID)
                .filter(Column("projectLocalID") == project.localID).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.localID, $0) })
            let context = try OfflineTaskRepository.makeAssemblyContext(accountID: accountID, db: db)
            let buckets = records.map { bucket in
                KanbanBucket(
                    id: bucket.remoteID, title: bucket.title,
                    isDoneBucket: bucket.remoteID == view.doneBucketID, limit: bucket.limit,
                    tasks: assignments.filter { $0.bucketLocalID == bucket.localID }.compactMap {
                        guard !hidden.contains($0.taskLocalID), let row = byID[$0.taskLocalID] else { return nil }
                        return OfflineTaskRepository.task(from: row, context: context)
                    },
                )
            }
            return .available(KanbanBoard(
                viewID: view.remoteID, buckets: buckets, defaultBucketID: view.defaultBucketID,
                supportsWrites: view.mode == "manual"
                    && view.filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                lastPulledAt: pulledAt,
            ))
        }
    }
}
