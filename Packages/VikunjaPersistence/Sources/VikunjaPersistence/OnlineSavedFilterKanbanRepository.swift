import Foundation
import GRDB
import VikunjaCore

/// Transitional online source behind the same contract as durable project boards.
/// Queries read an in-memory snapshot; only explicit refresh and commands use the network.
/// Task fields are shared with List/detail, while cross-project bucket membership is not persisted.
public actor OnlineSavedFilterKanbanRepository: KanbanBoardRepositoryProtocol,
    KanbanTaskOrderingProtocol, SyncTriggering {
    private let projectID: EntityID
    private let localStore: LocalStore
    private let accountID: UUID
    private let transport: BucketRepositoryProtocol
    private var board: KanbanBoard?
    private var taskPositions: [Int: Double] = [:]
    private var isReordering = false

    public init(
        projectID: EntityID, localStore: LocalStore, accountID: UUID, transport: BucketRepositoryProtocol,
    ) {
        self.projectID = projectID
        self.localStore = localStore
        self.accountID = accountID
        self.transport = transport
    }

    public func hasCachedKanbanSupport() async throws -> Bool {
        board != nil
    }

    public func hasInitialSnapshot() async throws -> Bool {
        board != nil
    }

    public func prepare() async throws {
        try await refresh(scope: .kanban(projectID: projectID))
    }

    public func fetchBoard(projectID: EntityID, viewID: Int?) async throws -> KanbanBoardSnapshot {
        guard projectID == self.projectID, let board, viewID == nil || viewID == board.viewID else {
            return .unavailable
        }
        // Canonical fields may have changed through List/detail since the last board download.
        return try await localStore.read { db in
            let rows = try TaskRecord.filter(Column("accountID") == self.accountID).fetchAll(db)
            let context = try OfflineTaskRepository.makeAssemblyContext(accountID: self.accountID, db: db)
            let byID = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                row.remoteID.map { ($0, row) }
            })
            let deleted = try SyncEngine.pendingDeleteRemoteIDs(accountID: self.accountID, entityType: .task, db: db)
            var buckets = board.buckets
            for index in buckets.indices {
                buckets[index].tasks = buckets[index].tasks.compactMap { task in
                    if deleted.contains(task.id.remoteValue ?? 0) {
                        return nil
                    }
                    guard let id = task.id.remoteValue, let row = byID[id] else { return task }
                    return OfflineTaskRepository.task(from: row, context: context)
                }
            }
            return .available(KanbanBoard(
                viewID: board.viewID, buckets: buckets, defaultBucketID: board.defaultBucketID,
                supportsWrites: board.supportsWrites, lastPulledAt: board.lastPulledAt,
                supportsTaskCreation: false, requiresConnection: true,
            ))
        }
    }

    public func refresh(scope: SyncScope) async throws {
        guard scope == .kanban(projectID: projectID), let remoteID = projectID.remoteValue,
              remoteID < -1 else { throw VikunjaError.notFound }
        let download = try await transport.downloadBoard(projectID: remoteID, viewID: board?.viewID)
        try await cache(download.buckets.flatMap(\.tasks))
        taskPositions = download.taskPositions
        board = KanbanBoard(
            viewID: download.viewID, buckets: download.buckets, defaultBucketID: download.defaultBucketID,
            supportsWrites: download.mode == "manual", lastPulledAt: Date(),
            supportsTaskCreation: false, requiresConnection: true,
        )
    }

    public func reorderTask(
        taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int, placement: KanbanTaskPlacement,
    ) async throws {
        guard !isReordering, projectID == self.projectID, let remoteID = taskID.remoteValue,
              let projectRemoteID = projectID.remoteValue else { throw VikunjaError.notFound }
        isReordering = true
        defer { isReordering = false }
        try await refresh(scope: .kanban(projectID: projectID))
        guard let board, board.viewID == viewID, board.supportsWrites else { throw VikunjaError.notFound }
        let download = KanbanDownload(
            viewID: board.viewID, mode: "manual", filterQuery: "", defaultBucketID: board.defaultBucketID,
            doneBucketID: nil, buckets: board.buckets, taskPositions: taskPositions,
        )
        guard let position = try placement.position(in: download, taskID: remoteID, bucketID: bucketID) else { return }
        try await localStore.read { db in
            let deleted = try SyncEngine.pendingDeleteRemoteIDs(accountID: self.accountID, entityType: .task, db: db)
            guard !deleted.contains(remoteID) else { throw SyncIncompleteError() }
            if let task = try TaskRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("remoteID") == remoteID).fetchOne(db),
                try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("targetLocalID") == task.localID).fetchCount(db) > 0 {
                throw SyncIncompleteError()
            }
        }
        _ = try await transport.setTaskPosition(taskID: remoteID, viewID: viewID, position: position)
        // Re-read every position because a write can renormalize the view.
        try await refresh(scope: .kanban(projectID: .remote(projectRemoteID)))
    }

    public func moveTask(
        taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int,
    ) async throws -> VikunjaTask {
        guard projectID == self.projectID, let remoteID = projectID.remoteValue,
              let taskRemoteID = taskID.remoteValue, let board, board.viewID == viewID, board.supportsWrites,
              board.buckets.contains(where: { $0.id == bucketID }),
              board.buckets.contains(where: { $0.tasks.contains { $0.id == taskID } })
        else { throw VikunjaError.notFound }
        // Do not bypass a queued edit/delete/movement for the same canonical task.
        try await localStore.read { db in
            let deleted = try SyncEngine.pendingDeleteRemoteIDs(accountID: self.accountID, entityType: .task, db: db)
            guard !deleted.contains(taskRemoteID) else { throw SyncIncompleteError() }
            let row = try TaskRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("remoteID") == taskRemoteID).fetchOne(db)
            if let row, try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("entityType") == MutationEntityType.task.rawValue)
                .filter(Column("targetLocalID") == row.localID).fetchCount(db) > 0 {
                throw SyncIncompleteError()
            }
        }
        let moved = try await transport.moveTask(
            taskID: taskRemoteID, toBucketID: bucketID, projectID: remoteID, viewID: viewID,
        )
        try await cache([moved])
        // Server rules may change membership or completion; always reload the authoritative board.
        try await refresh(scope: .kanban(projectID: projectID))
        return moved
    }

    public func createTask(
        title: String, projectID: EntityID, viewID: Int, bucketID: Int,
    ) async throws -> VikunjaTask {
        // A saved filter cannot choose the owning real project for a new task.
        throw VikunjaError.notFound
    }

    private func cache(_ tasks: [VikunjaTask]) async throws {
        try await localStore.write { db in
            try SyncEngine.cacheOnlineBoardTasks(tasks, accountID: self.accountID, db: db)
        }
    }
}
