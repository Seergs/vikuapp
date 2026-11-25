import Foundation
import GRDB
import VikunjaCore

public struct OfflineKanbanBoardRepository: KanbanBoardRepositoryProtocol {
    let localStore: LocalStore
    let accountID: UUID
    let syncRequester: SyncRequesting
    private let reachability: ReachabilityMonitoring?

    public init(
        localStore: LocalStore, accountID: UUID, syncRequester: SyncRequesting,
        reachability: ReachabilityMonitoring? = nil,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
        self.reachability = reachability
    }

    public func hasCachedKanbanSupport() async throws -> Bool {
        try await localStore.read { db in
            if try KanbanViewRecord.filter(Column("accountID") == accountID)
                .filter(Column("lastCompletePullAt") != nil).fetchCount(db) > 0 {
                return true
            }
            return try KanbanViewCatalogRecord.filter(Column("accountID") == accountID)
                .fetchAll(db).contains { !$0.views.isEmpty }
        }
    }

    public func fetchBoardCatalog(projectID: EntityID) async throws -> [KanbanViewSummary]? {
        try await localStore.read { db in
            guard let project = try Self.project(id: projectID, accountID: accountID, db: db) else { return nil }
            return try KanbanViewCatalogRecord.fetchOne(db, key: project.localID)?.views
        }
    }

    private static func project(id: EntityID, accountID: UUID, db: Database) throws -> ProjectRecord? {
        try ProjectRecord.filter(Column("accountID") == accountID).fetchAll(db).first {
            id == .local($0.localID) || $0.remoteID.map(EntityID.remote) == id
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

    public func setCompletion(
        taskID: EntityID, projectID: EntityID, viewID: Int, isDone: Bool,
    ) async throws -> VikunjaTask {
        guard case let .available(board) = try await fetchBoard(projectID: projectID, viewID: viewID),
              board.supportsWrites, board.buckets.contains(where: { $0.tasks.contains { $0.id == taskID } })
        else { throw VikunjaError.notFound }
        let tasks = OfflineTaskRepository(localStore: localStore, accountID: accountID, syncRequester: syncRequester)
        let updated = try await tasks.setCompletion(taskIDs: [taskID], isDone: isDone)
        guard let task = updated.first else { throw VikunjaError.notFound }
        return task
    }

    public func createTask(
        title: String, projectID: EntityID, viewID: Int, bucketID: Int,
    ) async throws -> VikunjaTask {
        let createdOnline = await reachability?.isReachable ?? false
        let created = try await localStore.write { db in
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let project = try Self.project(id: projectID, accountID: accountID, db: db),
                  let remoteID = project.remoteID, remoteID > 0, !project.isArchived,
                  let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
                  .filter(Column("remoteID") == viewID).fetchOne(db),
                  KanbanLocalMutations.supports(view),
                  let bucket = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                  .filter(Column("remoteID") == bucketID).fetchOne(db)
            else { throw VikunjaError.notFound }
            try KanbanCapacity.check(bucket, db: db)
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
            let position = try KanbanLocalMutations.firstPosition(view.localID, db: db)
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
                kanbanCreatedOnline: createdOnline,
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
            guard let project = try Self.project(id: projectID, accountID: accountID, db: db)
            else { return .unavailable }
            guard project.remoteID != nil else { return .waitingForProject }
            let catalog = try KanbanViewCatalogRecord.fetchOne(db, key: project.localID)?.views
            if let catalog, catalog.isEmpty {
                return .unavailable
            }
            let selectedID = viewID ?? catalog?.first?.id
            var query = KanbanViewRecord.filter(Column("accountID") == accountID)
                .filter(Column("projectLocalID") == project.localID)
            if let selectedID {
                query = query.filter(Column("remoteID") == selectedID)
            }
            guard let view = try query.order(Column("remoteID")).fetchOne(db),
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
                supportsWrites: KanbanLocalMutations.supports(view),
                lastPulledAt: pulledAt,
            ))
        }
    }
}
