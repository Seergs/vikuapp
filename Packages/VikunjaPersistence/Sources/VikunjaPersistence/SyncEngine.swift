import Foundation
import GRDB
import os
import VikunjaCore

private let syncLogger = Logger(subsystem: "dev.sergiosuarez.vikunja", category: "sync")

/// Keeps one account's slice of the local store's cache in step with the
/// server: pulls the server's state in, and drains that account's locally
/// queued mutations back out.
public actor SyncEngine {
    var activeKanbanCreations: Set<Int64> = []
    let bucketRepository: BucketRepositoryProtocol?
    let capabilityProvider: CapabilityProvider
    let localStore: LocalStore
    private let projectRepository: ProjectRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let taskRepository: TaskRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    /// `nil` in tests/constructions that never touch comments. Every real
    /// `SyncEngine` built by the app or `SyncCoordinator` passes one.
    private let commentRepository: TaskCommentRepositoryProtocol?
    /// `nil` for engine instances that do not drain saved-filter writes.
    private let filterRepository: FilterRepositoryProtocol?
    /// `InstanceAccount.id` — every row this engine reads or writes is
    /// scoped to this one account, since `LocalStore`'s tables hold every
    /// saved account's data together rather than one database file each.
    let accountID: UUID

    public init(
        localStore: LocalStore,
        projectRepository: ProjectRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        taskRepository: TaskRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        commentRepository: TaskCommentRepositoryProtocol? = nil,
        filterRepository: FilterRepositoryProtocol? = nil,
        accountID: UUID,
        bucketRepository: BucketRepositoryProtocol? = nil,
        capabilityProvider: CapabilityProvider = NoopCapabilityProvider(),
    ) {
        self.bucketRepository = bucketRepository
        self.capabilityProvider = capabilityProvider
        self.localStore = localStore
        self.projectRepository = projectRepository
        self.labelRepository = labelRepository
        self.taskRepository = taskRepository
        self.relationRepository = relationRepository
        self.commentRepository = commentRepository
        self.filterRepository = filterRepository
        self.accountID = accountID
    }

    /// Pull before draining to preserve timestamp-based conflict detection.
    /// Each phase is independent: healthy data is committed even if another
    /// request fails. Remaining queue entries make partial uploads observable.
    public func synchronize() async throws {
        let phases: [@Sendable () async throws -> Void] = [
            { try await self.pullProjects() },
            { try await self.drainProjectMutations() },
            { try await self.drainFilterMutations() },
            { try await self.pullFilterQueries() },
            { try await self.pullLabels() },
            { try await self.drainLabelMutations() },
            { try await self.pullTasks() },
            { try await self.drainTaskMutations() },
            { try await self.drainCommentMutations() },
        ]
        var firstError: (any Error)?
        for phase in phases {
            do { try await phase() } catch { firstError = firstError ?? error }
        }
        if let firstError {
            throw firstError
        }
        let hasPendingWork = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db).contains { $0.accountID == self.accountID }
        }
        if hasPendingWork {
            throw SyncIncompleteError()
        }
    }

    /// Explicit demand-load. A failed download never enters the database transaction.
    public func pullKanban(projectID: EntityID) async throws {
        guard let bucketRepository, await capabilityProvider.supports(.apiV2) else { return }
        let project = try await localStore.read { db in
            try ProjectRecord.fetchAll(db).first {
                $0.accountID == self.accountID && (projectID == .local($0.localID)
                    || $0.remoteID.map(EntityID.remote) == projectID)
            }
        }
        guard let project, let remoteID = project.remoteID, remoteID > 0 else { throw VikunjaError.notFound }
        let existingView = try await localStore.read { db in
            try KanbanViewRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("projectLocalID") == project.localID).order(Column("remoteID")).fetchOne(db)
        }
        let download = try await bucketRepository.downloadBoard(projectID: remoteID, viewID: existingView?.remoteID)
        try await localStore.write { db in
            // The project may have disappeared while the network request was running.
            guard let current = try ProjectRecord.fetchOne(db, key: project.localID),
                  current.accountID == self.accountID, current.remoteID == remoteID
            else { throw VikunjaError.notFound }
            try self.storeKanban(download, project: current, db: db)
        }
    }

    private nonisolated func storeKanban(_ download: KanbanDownload, project: ProjectRecord, db: Database) throws {
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
        let protected = Set(queue.filter { $0.entityType == .task }.map(\.targetLocalID))
        let deleted = Set(queue.filter { $0.entityType == .task && $0.operation == .delete }.map(\.targetLocalID))
        let rows = try TaskRecord.filter(Column("accountID") == accountID).fetchAll(db)
        let identities = try Self.upsertKanbanTasks(
            download, project: project, rows: rows, intent: (protected, deleted), db: db,
        )
        var view = try KanbanViewRecord.filter(Column("accountID") == accountID)
            .filter(Column("projectLocalID") == project.localID)
            .filter(Column("remoteID") == download.viewID).fetchOne(db)
            ?? KanbanViewRecord(
                localID: UUID(),
                accountID: accountID,
                projectLocalID: project.localID,
                remoteID: download.viewID,
                mode: download.mode,
                filterQuery: download.filterQuery,
            )
        view.mode = download.mode
        view.filterQuery = download.filterQuery
        view.defaultBucketID = download.defaultBucketID
        view.doneBucketID = download.doneBucketID
        view.lastCompletePullAt = Date()
        try view.save(db)
        let assignments = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID).fetchAll(db)
        let preserved = assignments.filter { protected.contains($0.taskLocalID) && !deleted.contains($0.taskLocalID) }
        try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
            .filter(!preserved.map(\.taskLocalID).contains(Column("taskLocalID"))).deleteAll(db)
        var keptBucketIDs = Set(preserved.map(\.bucketLocalID))
        for (index, bucket) in download.buckets.enumerated() {
            let row = try Self.saveKanbanBucket(bucket, position: index, view: view, db: db)
            keptBucketIDs.insert(row.localID)
            for (position, task) in bucket.tasks.enumerated() {
                guard let id = task.id.remoteValue, let localID = identities[id], !deleted.contains(localID),
                      !preserved.contains(where: { $0.taskLocalID == localID }),
                      let canonical = try TaskRecord.fetchOne(db, key: localID),
                      canonical.projectLocalID == project.localID
                else { continue }
                try KanbanAssignmentRecord(
                    accountID: accountID,
                    projectLocalID: project.localID,
                    viewLocalID: view.localID,
                    bucketLocalID: row.localID,
                    taskLocalID: localID,
                    position: Double(position),
                ).insert(db)
            }
        }
        try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
            .filter(!keptBucketIDs.contains(Column("localID"))).deleteAll(db)
        for assignment in preserved {
            let bucket = try KanbanBucketRecord.fetchOne(db, key: assignment.bucketLocalID)
            guard download.buckets.contains(where: { $0.id == bucket?.remoteID }) else {
                // Abort this transaction, retaining the last complete board and pending work.
                throw VikunjaError.notFound
            }
        }
    }

    private static func upsertKanbanTasks(
        _ download: KanbanDownload, project: ProjectRecord, rows: [TaskRecord],
        intent: (protected: Set<UUID>, deleted: Set<UUID>), db: Database,
    ) throws -> [Int: UUID] {
        guard let remoteProjectID = project.remoteID else { throw VikunjaError.notFound }
        let tasks = download.buckets.flatMap(\.tasks)
        guard Set(download.buckets.map(\.id)).count == download.buckets.count,
              Set(tasks.map(\.id)).count == tasks.count,
              tasks.allSatisfy({ $0.id.remoteValue != nil && $0.projectID == .remote(remoteProjectID) })
        else { throw VikunjaError.decoding("Invalid Kanban snapshot identity") }
        let identities = Self.reserveTaskLocalIDs(for: tasks, existing: rows)
        try Self.upsertTaskRows(
            for: tasks.filter { task in
                guard let id = task.id.remoteValue, let localID = identities[id] else { return false }
                return !intent.deleted.contains(localID)
            },
            accountID: project.accountID, localIDByRemoteID: identities,
            projectLocalIDByRemoteID: [remoteProjectID: project.localID], protectedLocalIDs: intent.protected, db: db,
        )
        return identities
    }

    private static func saveKanbanBucket(
        _ bucket: KanbanBucket, position: Int, view: KanbanViewRecord, db: Database,
    ) throws -> KanbanBucketRecord {
        var row = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
            .filter(Column("remoteID") == bucket.id).fetchOne(db)
            ?? KanbanBucketRecord(
                localID: UUID(), accountID: view.accountID, projectLocalID: view.projectLocalID,
                viewLocalID: view.localID, remoteID: bucket.id, title: bucket.title,
                position: Double(position), limit: bucket.limit, serverCount: bucket.tasks.count,
            )
        row.title = bucket.title
        row.position = Double(position)
        row.limit = bucket.limit
        row.serverCount = bucket.tasks.count
        try row.save(db)
        return row
    }

    /// Saved-filter queries are part of the offline snapshot, not a hidden
    /// network side effect of reading a filter's detail.
    public func pullFilterQueries() async throws {
        guard let filterRepository else { return }
        let filters = try await localStore.read { db in
            try SavedFilterRecord.fetchAll(db).filter { $0.accountID == self.accountID }
        }
        var firstError: (any Error)?
        for filter in filters {
            do {
                let detail = try await filterRepository.fetchFilter(id: filter.remoteID)
                try await localStore.write { db in
                    guard var current = try SavedFilterRecord.fetchOne(db, key: filter.projectLocalID) else { return }
                    try current.storeQuery(detail.query, pulledAt: Date(), db: db)
                }
            } catch { firstError = firstError ?? error }
        }
        if let firstError {
            throw firstError
        }
    }

    /// Fetches every project from the server and reconciles it into the
    /// local store: upserts each one by its remote id, deletes a local row
    /// whose remote id is no longer present in the server's response
    /// (unless a mutation is still queued against it — that row might be a
    /// local edit the pull hasn't confirmed yet, not a real server-side
    /// deletion), and records this as the most recent full pull.
    ///
    /// Always a full reconciliation, never a partial one: the server has no
    /// way to filter the project list by `updated`, so there's no cheaper
    /// incremental fetch to fall back to between full pulls the way there
    /// will be for an entity whose list endpoint does support that.
    public func pullProjects() async throws {
        let pulled = try await projectRepository.fetchProjects()
        let now = Date()

        try await localStore.write { db in
            let deletedIDs = try Self.pendingDeleteRemoteIDs(accountID: self.accountID, entityType: .project, db: db)
            let remoteProjects = pulled.filter { !deletedIDs.contains($0.id.remoteValue ?? 0) }
            let localRows = try ProjectRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            let localIDByRemoteID = Self.reserveLocalIDs(for: remoteProjects, existing: localRows)
            let queuedTargetLocalIDs = try Self.queuedTargetLocalIDs(
                accountID: self.accountID, entityType: .project, db: db,
            ).union(Self.queuedTargetLocalIDs(accountID: self.accountID, entityType: .filter, db: db))

            try Self.upsertRows(
                for: remoteProjects, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
            )
            try Self.resolveParentLinks(
                for: remoteProjects, localIDByRemoteID: localIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
            )
            try Self.ensureSavedFilterRows(
                for: remoteProjects, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID, db: db,
            )
            try Self.deleteMissingRows(
                localRows,
                stillPresentRemoteIDs: Set(remoteProjects.compactMap(\.id.remoteValue)),
                protectedLocalIDs: queuedTargetLocalIDs,
                db: db,
            )

            try SyncStateRecord(accountID: self.accountID, entityType: .project, lastPulledAt: now).save(db)
        }
    }

    /// A localID for every remote project: an existing row's own, or a
    /// fresh `UUID` for one not seen before. Resolved up front so a child's
    /// parent link can be looked up below regardless of array order.
    /// `existing` is already scoped to this engine's account, so `remoteID`
    /// only needs to be unique within it, not across every saved account.
    private static func reserveLocalIDs(
        for remoteProjects: [Project],
        existing localRows: [ProjectRecord],
    ) -> [Int: UUID] {
        var localIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: localRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, localIDByRemoteID[remoteID] == nil else { continue }
            localIDByRemoteID[remoteID] = UUID()
        }
        return localIDByRemoteID
    }

    /// The saved-filter table is a query cache keyed by the pseudo-project's
    /// local id. `/projects` can introduce new filters after the migration's
    /// one-time backfill, so every project pull ensures their cache rows exist.
    private static func ensureSavedFilterRows(
        for remoteProjects: [Project],
        accountID: UUID,
        localIDByRemoteID: [Int: UUID],
        db: Database,
    ) throws {
        for project in remoteProjects {
            guard let remoteID = project.savedFilterID,
                  let pseudoProjectID = project.id.remoteValue,
                  let localID = localIDByRemoteID[pseudoProjectID],
                  try SavedFilterRecord.fetch(projectLocalID: localID, db: db) == nil
            else { continue }
            try SavedFilterRecord(
                projectLocalID: localID,
                accountID: accountID,
                remoteID: remoteID,
                query: "",
                lastPulledAt: nil,
            ).insert(db)
        }
    }

    /// Inserts or updates every remote project, with no parent link yet: a
    /// child can appear before its parent in `remoteProjects`, and
    /// `parentProjectLocalID`'s foreign key would reject pointing at a row
    /// that doesn't exist in the table yet.
    ///
    /// A row in `protectedLocalIDs` keeps its own content (title,
    /// description, ...) instead of taking the server's still-stale
    /// response - a mutation queued against it means there's a local edit
    /// the server doesn't reflect yet, and overwriting that content would
    /// silently discard the edit until the next pull after the queue
    /// finally drains. Its `serverUpdatedAt` is still refreshed, though:
    /// that's what `drainUpdate`'s conflict check compares the queued
    /// mutation's own baseline against, and skipping it here would make
    /// a real conflict (someone else edited this project in the meantime)
    /// invisible until a pull happens to run again after the local edit
    /// has already drained.
    private static func upsertRows(
        for remoteProjects: [Project],
        accountID: UUID,
        localIDByRemoteID: [Int: UUID],
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            if protectedLocalIDs.contains(localID) {
                guard var existing = try ProjectRecord.fetchOne(db, key: localID) else { continue }
                existing.serverUpdatedAt = project.updated
                try existing.save(db)
                continue
            }
            let row = ProjectRecord(
                localID: localID,
                accountID: accountID,
                remoteID: remoteID,
                title: project.title,
                description: project.description,
                isArchived: project.isArchived,
                isFavorite: project.isFavorite,
                parentProjectLocalID: nil,
                position: project.position,
                hexColor: project.hexColor,
                serverUpdatedAt: project.updated,
            )
            try row.save(db)
        }
    }

    /// Every row from `upsertRows` already exists by now, so setting a
    /// non-nil parent link in this second pass can't hit the foreign-key
    /// ordering problem that method avoids. Same `protectedLocalIDs` skip as
    /// `upsertRows` - a row with its own local edit queued (which could be a
    /// re-parent) shouldn't have its parent link silently overwritten either.
    private static func resolveParentLinks(
        for remoteProjects: [Project],
        localIDByRemoteID: [Int: UUID],
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            guard !protectedLocalIDs.contains(localID) else { continue }
            guard let parentLocalID = project.parentProjectID?.remoteValue.flatMap({ localIDByRemoteID[$0] }) else {
                continue
            }
            guard var row = try ProjectRecord.fetchOne(db, key: localID) else { continue }
            row.parentProjectLocalID = parentLocalID
            try row.save(db)
        }
    }

    /// Target ids with a mutation still queued against them (pending,
    /// in-flight, or failed-but-retryable) — shared by `upsertRows`,
    /// `resolveParentLinks`, and `deleteMissingRows` to decide what a pull
    /// must leave untouched, since any of those rows holds a local edit the
    /// server doesn't reflect back yet.
    ///
    /// Excludes a conflicted item on purpose: once `drainUpdate` has flagged
    /// one, it can never drain again without a conflict-resolution UI this
    /// app doesn't have yet, so protecting its row forever would leave the
    /// local cache permanently stuck showing the discarded local edit
    /// instead of the server's real state - worse than just letting the
    /// next pull resync it to the truth. The queue item itself still sticks
    /// around with `needsConflictResolution` set, in case a future UI wants
    /// to read it back.
    private static func pendingDeleteRemoteIDs(
        accountID: UUID, entityType: MutationEntityType, db: Database,
    ) throws -> Set<Int> {
        let items = try MutationQueueRecord.fetchAll(db).filter {
            $0.accountID == accountID && $0.entityType == entityType && $0.operation == .delete
        }
        return try Set(items.compactMap { item in
            switch entityType {
            case .project: try decode(ProjectDeletePayload.self, from: item.payload)?.remoteID
            case .task: try decode(TaskDeletePayload.self, from: item.payload)?.remoteID
            case .label: try decode(LabelDeletePayload.self, from: item.payload)?.remoteID
            case .comment: try decode(TaskCommentDeletePayload.self, from: item.payload)?.remoteID
            case .filter: try decode(FilterDeletePayload.self, from: item.payload)?.remoteID
            }
        })
    }

    private static func queuedTargetLocalIDs(
        accountID: UUID,
        entityType: MutationEntityType,
        db: Database,
    ) throws -> Set<UUID> {
        try Set(
            MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == accountID && $0.entityType == entityType && !$0.needsConflictResolution
                        && ($0.status == .pending || $0.status == .inFlight || $0.status == .failed)
                }
                .map(\.targetLocalID),
        )
    }

    /// Drops a local row whose remote id is no longer in the server's
    /// response, unless a mutation is still queued against it — that row
    /// might be a local edit the pull hasn't confirmed yet, not a real
    /// server-side deletion. `localRows` is already scoped to `accountID`.
    private static func deleteMissingRows(
        _ localRows: [ProjectRecord],
        stillPresentRemoteIDs: Set<Int>,
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for row in localRows {
            guard let remoteID = row.remoteID, !stillPresentRemoteIDs.contains(remoteID) else { continue }
            guard !protectedLocalIDs.contains(row.localID) else { continue }
            try row.delete(db)
        }
    }

    // MARK: - Pulling labels

    /// Fetches every label from the server and reconciles it into the local
    /// store — same shape as `pullProjects()`, minus the parent-link pass:
    /// labels have no hierarchy, so nothing depends on draining in a
    /// particular order the way a sub-project does.
    public func pullLabels() async throws {
        let pulled = try await labelRepository.fetchLabels()
        let now = Date()

        try await localStore.write { db in
            let deletedIDs = try Self.pendingDeleteRemoteIDs(accountID: self.accountID, entityType: .label, db: db)
            let remoteLabels = pulled.filter { !deletedIDs.contains($0.id.remoteValue ?? 0) }
            let localRows = try LabelRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            let localIDByRemoteID = Self.reserveLabelLocalIDs(for: remoteLabels, existing: localRows)
            let queuedTargetLocalIDs = try Self.queuedTargetLocalIDs(
                accountID: self.accountID, entityType: .label, db: db,
            )

            try Self.upsertLabelRows(
                for: remoteLabels, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
            )
            try Self.deleteMissingLabelRows(
                localRows,
                stillPresentRemoteIDs: Set(remoteLabels.compactMap(\.id.remoteValue)),
                protectedLocalIDs: queuedTargetLocalIDs,
                db: db,
            )

            try SyncStateRecord(accountID: self.accountID, entityType: .label, lastPulledAt: now).save(db)
        }
    }

    private static func reserveLabelLocalIDs(
        for remoteLabels: [Label],
        existing localRows: [LabelRecord],
    ) -> [Int: UUID] {
        var localIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: localRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        for label in remoteLabels {
            guard let remoteID = label.id.remoteValue, localIDByRemoteID[remoteID] == nil else { continue }
            localIDByRemoteID[remoteID] = UUID()
        }
        return localIDByRemoteID
    }

    /// Same `protectedLocalIDs` skip as `upsertRows` - see its doc comment.
    /// Unlike projects, a label never refreshes anything on a protected row:
    /// there's no `serverUpdatedAt` to keep current, since labels carry no
    /// conflict-detection baseline at all (see `LabelCreateOrUpdatePayload`).
    private static func upsertLabelRows(
        for remoteLabels: [Label],
        accountID: UUID,
        localIDByRemoteID: [Int: UUID],
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for label in remoteLabels {
            guard let remoteID = label.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            guard !protectedLocalIDs.contains(localID) else { continue }
            let row = LabelRecord(
                localID: localID,
                accountID: accountID,
                remoteID: remoteID,
                title: label.title,
                hexColor: label.hexColor,
            )
            try row.save(db)
        }
    }

    private static func deleteMissingLabelRows(
        _ localRows: [LabelRecord],
        stillPresentRemoteIDs: Set<Int>,
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for row in localRows {
            guard let remoteID = row.remoteID, !stillPresentRemoteIDs.contains(remoteID) else { continue }
            guard !protectedLocalIDs.contains(row.localID) else { continue }
            try row.delete(db)
        }
    }

    // MARK: - Pulling tasks

    private struct VirtualTaskSnapshot {
        let projectLocalID: UUID
        let tasks: [VikunjaTask]
    }

    private struct TaskPullResult {
        let tasks: [VikunjaTask]
        let fetchedProjectLocalIDs: Set<UUID>
        let virtualSnapshots: [VirtualTaskSnapshot]
        let firstError: (any Error)?
    }

    /// Fetches tasks for real and virtual projects after the project pull.
    /// Real projects own task records; negative-id virtual projects add
    /// membership snapshots without changing a task's owning project.
    /// Each snapshot is replaced only after its own fetch succeeds, so a
    /// partial network failure never wipes the last usable offline copy.
    public func pullTasks() async throws {
        let now = Date()
        let projectRows = try await localStore.read { db in
            try ProjectRecord.fetchAll(db).filter { $0.accountID == self.accountID }
        }
        let result = await fetchTaskPullResult(projectRows: projectRows)
        try await applyTaskPullResult(result, projectRows: projectRows, pulledAt: now)
        if let firstError = result.firstError {
            throw firstError
        }
    }

    private func fetchTaskPullResult(projectRows: [ProjectRecord]) async -> TaskPullResult {
        var remoteTasks: [VikunjaTask] = []
        var fetchedProjectLocalIDs: Set<UUID> = []
        var virtualSnapshots: [VirtualTaskSnapshot] = []
        var firstError: (any Error)?
        for projectRow in projectRows {
            guard let remoteProjectID = projectRow.remoteID else { continue }
            do {
                let tasks = try await taskRepository.fetchTasks(projectID: .remote(remoteProjectID))
                remoteTasks += tasks
                if remoteProjectID < 0 {
                    virtualSnapshots.append(VirtualTaskSnapshot(projectLocalID: projectRow.localID, tasks: tasks))
                } else if remoteProjectID > 0 {
                    fetchedProjectLocalIDs.insert(projectRow.localID)
                }
            } catch {
                firstError = firstError ?? error
            }
        }

        var tasksByRemoteID: [Int: VikunjaTask] = [:]
        for task in remoteTasks {
            guard let remoteID = task.id.remoteValue else { continue }
            tasksByRemoteID[remoteID] = task
        }
        let projectLocalIDByRemoteID = Dictionary(
            uniqueKeysWithValues: projectRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        for snapshot in virtualSnapshots {
            let unresolvedCount = snapshot.tasks.filter { task in
                guard let remoteID = task.projectID.remoteValue else { return true }
                return projectLocalIDByRemoteID[remoteID] == nil
            }.count
            if unresolvedCount > 0 {
                syncLogger.warning(
                    "Skipping \(unresolvedCount, privacy: .public) virtual task memberships with uncached projects.",
                )
            }
        }
        return TaskPullResult(
            tasks: Array(tasksByRemoteID.values),
            fetchedProjectLocalIDs: fetchedProjectLocalIDs,
            virtualSnapshots: virtualSnapshots,
            firstError: firstError,
        )
    }

    private func applyTaskPullResult(
        _ result: TaskPullResult,
        projectRows: [ProjectRecord],
        pulledAt: Date,
    ) async throws {
        let projectLocalIDByRemoteID = Dictionary(
            uniqueKeysWithValues: projectRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        let stillPresentRemoteIDs = Set(result.tasks.compactMap(\.id.remoteValue))
        try await localStore.write { db in
            let deletedIDs = try Self.pendingDeleteRemoteIDs(accountID: self.accountID, entityType: .task, db: db)
            let remoteTasks = result.tasks.filter { !deletedIDs.contains($0.id.remoteValue ?? 0) }
            let localRows = try TaskRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            let localIDByRemoteID = Self.reserveTaskLocalIDs(for: remoteTasks, existing: localRows)
            let queuedTargetLocalIDs = try Self.queuedTargetLocalIDs(
                accountID: self.accountID, entityType: .task, db: db,
            )
            try Self.upsertTaskRows(
                for: remoteTasks, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID,
                projectLocalIDByRemoteID: projectLocalIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
            )
            // Keep tasks returned from any successful endpoint so a task
            // moved projects isn't deleted by its old project's stale list.
            try Self.deleteMissingTaskRows(
                localRows.filter { result.fetchedProjectLocalIDs.contains($0.projectLocalID) },
                stillPresentRemoteIDs: stillPresentRemoteIDs,
                protectedLocalIDs: queuedTargetLocalIDs,
                db: db,
            )
            try Self.replaceVirtualTaskMemberships(
                result.virtualSnapshots,
                accountID: self.accountID,
                localIDByRemoteID: localIDByRemoteID,
                projectLocalIDByRemoteID: projectLocalIDByRemoteID,
                db: db,
            )
            if result.firstError == nil {
                try SyncStateRecord(accountID: self.accountID, entityType: .task, lastPulledAt: pulledAt).save(db)
            }
        }
    }

    private static func replaceVirtualTaskMemberships(
        _ snapshots: [VirtualTaskSnapshot],
        accountID: UUID,
        localIDByRemoteID: [Int: UUID],
        projectLocalIDByRemoteID: [Int: UUID],
        db: Database,
    ) throws {
        for snapshot in snapshots {
            try VirtualProjectTaskRecord
                .filter(Column("projectLocalID") == snapshot.projectLocalID)
                .deleteAll(db)
            for (position, task) in snapshot.tasks.enumerated() {
                guard let remoteID = task.id.remoteValue,
                      let taskLocalID = localIDByRemoteID[remoteID],
                      let projectRemoteID = task.projectID.remoteValue,
                      projectLocalIDByRemoteID[projectRemoteID] != nil else { continue }
                try VirtualProjectTaskRecord(
                    accountID: accountID,
                    projectLocalID: snapshot.projectLocalID,
                    taskLocalID: taskLocalID,
                    position: position,
                ).save(db)
            }
        }
    }

    /// Refreshes one task's cached comment thread from the server. Called
    /// on demand by `OfflineTaskCommentRepository.fetchComments` rather than
    /// from `SyncCoordinator`'s periodic pass: comments are a per-task
    /// resource, and pulling every cached task's thread would turn one sync
    /// into tens or hundreds of requests.
    ///
    /// A pending local create (no remote id yet) is never removed by a pull,
    /// and a comment with a queued update keeps its local text instead of
    /// being overwritten by the server's older copy. A queued delete already
    /// removed the local row, so its remote id is skipped on the way in to
    /// stop the pull resurrecting it before the delete drains.
    public func pullComments(taskID: EntityID) async throws {
        guard let commentRepository else { return }
        let taskRow = try await localStore.read { db in
            let rows = try TaskRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            switch taskID {
            case let .local(localID): return rows.first { $0.localID == localID }
            case let .remote(remoteID): return rows.first { $0.remoteID == remoteID }
            }
        }
        guard let taskRow, let taskRemoteID = taskRow.remoteID else { return }

        let remoteComments = try await commentRepository.fetchComments(taskID: .remote(taskRemoteID))
        let fetchedRemoteIDs = Set(remoteComments.compactMap(\.id.remoteValue))

        try await localStore.write { db in
            let localRows = try TaskCommentRecord.fetchAll(db)
                .filter { $0.accountID == self.accountID && $0.taskLocalID == taskRow.localID }
            let pendingItems = try MutationQueueRecord.fetchAll(db).filter {
                $0.accountID == self.accountID && $0.entityType == .comment
                    && ($0.status == .pending || $0.status == .failed)
            }
            let protectedLocalIDs = Set(pendingItems.map(\.targetLocalID))
            let hiddenRemoteIDs = Set(
                pendingItems.compactMap { item -> Int? in
                    guard item.operation == .delete else { return nil }
                    return (try? Self.decode(TaskCommentDeletePayload.self, from: item.payload))?.remoteID
                },
            )
            var localIDByRemoteID: [Int: UUID] = Dictionary(
                uniqueKeysWithValues: localRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
            )

            for comment in remoteComments {
                guard let remoteID = comment.id.remoteValue, !hiddenRemoteIDs.contains(remoteID) else { continue }
                let localID = localIDByRemoteID[remoteID] ?? UUID()
                localIDByRemoteID[remoteID] = localID
                if protectedLocalIDs.contains(localID) {
                    continue
                }
                try Self.saveComment(
                    comment, localID: localID, accountID: self.accountID, taskLocalID: taskRow.localID, db: db,
                )
            }

            for row in localRows {
                guard let remoteID = row.remoteID, !fetchedRemoteIDs.contains(remoteID) else { continue }
                guard !protectedLocalIDs.contains(row.localID), !hiddenRemoteIDs.contains(remoteID) else { continue }
                try row.delete(db)
            }
        }
    }

    private static func saveComment(
        _ comment: TaskComment, localID: UUID, accountID: UUID, taskLocalID: UUID, db: Database,
    ) throws {
        try TaskCommentRecord(
            localID: localID,
            accountID: accountID,
            remoteID: comment.id.remoteValue,
            taskLocalID: taskLocalID,
            comment: comment.comment,
            authorID: comment.author.id,
            authorUsername: comment.author.username,
            authorName: comment.author.name,
            authorEmail: comment.author.email,
            created: comment.created,
            updated: comment.updated,
        ).save(db)
    }

    private static func reserveTaskLocalIDs(
        for remoteTasks: [VikunjaTask],
        existing localRows: [TaskRecord],
    ) -> [Int: UUID] {
        var localIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: localRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        for task in remoteTasks {
            guard let remoteID = task.id.remoteValue, localIDByRemoteID[remoteID] == nil else { continue }
            localIDByRemoteID[remoteID] = UUID()
        }
        return localIDByRemoteID
    }

    // swiftlint:disable function_parameter_count
    /// Same `protectedLocalIDs` skip as `upsertRows` — see its doc comment.
    /// A task whose project can't be resolved locally (shouldn't happen
    /// given `pullProjects()` always runs first, but defensive against a
    /// task somehow referencing a project this account's pull hasn't seen)
    /// is skipped entirely: `projectLocalID` has no `NULL` to fall back to.
    private static func upsertTaskRows(
        for remoteTasks: [VikunjaTask],
        accountID: UUID,
        localIDByRemoteID: [Int: UUID],
        projectLocalIDByRemoteID: [Int: UUID],
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for task in remoteTasks {
            guard let remoteID = task.id.remoteValue, let localID = localIDByRemoteID[remoteID] else { continue }
            guard let projectRemoteID = task.projectID.remoteValue,
                  let projectLocalID = projectLocalIDByRemoteID[projectRemoteID] else { continue }
            let labelRemoteIDs = task.labels.compactMap(\.id.remoteValue).map(String.init).joined(separator: ",")
            if protectedLocalIDs.contains(localID) {
                guard var existing = try TaskRecord.fetchOne(db, key: localID) else { continue }
                existing.serverUpdatedAt = task.updated
                // Label association isn't part of the local edit being
                // protected here (that's core fields only), so this still
                // refreshes freely - same reasoning as `serverUpdatedAt`.
                existing.labelRemoteIDs = labelRemoteIDs
                try existing.save(db)
                // Keep the queued mutation's conflict baseline in sync with
                // the refreshed `serverUpdatedAt`, so a pull between edit and
                // drain doesn't trip a false conflict.
                try MutationQueueRecord.fetchAll(db)
                    .filter {
                        $0.accountID == accountID && $0.entityType == .task
                            && $0.targetLocalID == localID
                            && ($0.status == .pending || $0.status == .failed)
                    }
                    .forEach { record in
                        var updated = record
                        updated.baseUpdatedAt = task.updated
                        try updated.update(db)
                    }
                // Relation association isn't part of the local edit being
                // protected either - same reasoning as `labelRemoteIDs`.
                try Self.replaceRelationRows(for: localID, accountID: accountID, task: task, db: db)
                continue
            }
            let row = TaskRecord(
                localID: localID,
                accountID: accountID,
                remoteID: remoteID,
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                serverUpdatedAt: task.updated,
                labelRemoteIDs: labelRemoteIDs,
            )
            // The task row has to exist before its relations: `taskRelation`
            // has a foreign key on `task.localID`, so inserting a relation
            // for a newly pulled task first used to fail on a cache miss.
            try row.save(db)
            try Self.replaceRelationRows(for: localID, accountID: accountID, task: task, db: db)
            try TaskReminderRecord.replace(
                for: localID, accountID: accountID, reminders: task.reminders, db: db,
            )
        }
    }

    // swiftlint:enable function_parameter_count

    /// Fully replaces one task's cached relation set — delete then
    /// re-insert, rather than diffing - since the server's `related_tasks`
    /// map returned alongside the task is itself already the full set, same
    /// "full reconciliation" approach `pullProjects`/`pullLabels` take for
    /// their own tables.
    private static func replaceRelationRows(
        for localID: UUID,
        accountID: UUID,
        task: VikunjaTask,
        db: Database,
    ) throws {
        try TaskRelationRecord.filter(Column("taskLocalID") == localID).deleteAll(db)
        var relations: [(kind: RelationKind, relation: TaskRelation)] = []
        relations += task.subtasks.map { (kind: .subtask, relation: $0) }
        relations += task.dependsOn.map { (kind: .blocked, relation: $0) }
        relations += task.blocks.map { (kind: .blocking, relation: $0) }
        for (kind, kindRelations) in task.otherRelations {
            relations += kindRelations.map { (kind: kind, relation: $0) }
        }
        for (kind, relation) in relations {
            guard let otherTaskRemoteID = relation.id.remoteValue,
                  let otherProjectRemoteID = relation.projectID.remoteValue else { continue }
            let row = TaskRelationRecord(
                localID: UUID(), accountID: accountID, taskLocalID: localID, kind: kind,
                otherTaskRemoteID: otherTaskRemoteID, otherProjectRemoteID: otherProjectRemoteID,
                title: relation.title, isDone: relation.isDone,
            )
            try row.insert(db)
        }
    }

    private static func deleteMissingTaskRows(
        _ localRows: [TaskRecord],
        stillPresentRemoteIDs: Set<Int>,
        protectedLocalIDs: Set<UUID>,
        db: Database,
    ) throws {
        for row in localRows {
            guard let remoteID = row.remoteID, !stillPresentRemoteIDs.contains(remoteID) else { continue }
            guard !protectedLocalIDs.contains(row.localID) else { continue }
            // The task's comment rows go with it via the FK cascade, so any
            // comment mutation still queued for one of them can never be
            // addressed again — drop it here instead of leaving it to defer
            // forever.
            let commentLocalIDs = try Set(
                TaskCommentRecord.fetchAll(db)
                    .filter { $0.accountID == row.accountID && $0.taskLocalID == row.localID }
                    .map(\.localID),
            )
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == row.accountID && $0.entityType == .comment
                        && commentLocalIDs.contains($0.targetLocalID)
                        && ($0.status == .pending || $0.status == .failed)
                }
                .forEach { try $0.delete(db) }
            try row.delete(db)
        }
    }

    // MARK: - Draining queued mutations

    enum DrainError: Error {
        /// `payload` was nil, or didn't decode as the shape its `operation` expects.
        case invalidPayload
    }

    /// Replays every queued, non-conflicted project mutation against the
    /// server, oldest first. A `create`/`update` whose payload references a
    /// parent project that hasn't itself synced yet (no remote id) is left
    /// in the queue for a later drain pass — by processing in the order
    /// mutations were queued, a parent's own `create` (necessarily queued
    /// before any child that references it) has already run earlier in
    /// this same pass if it's going to succeed at all, so this only
    /// actually defers anything when the parent's own create is still
    /// failing. One item's failure doesn't stop the rest from draining.
    ///
    /// Includes `.failed` items alongside `.pending` ones — a drain that
    /// failed once (a dead token, a momentary 500, ...) still deserves
    /// another shot on the very next trigger, rather than being stuck
    /// invisibly forever just because one earlier attempt didn't work.
    /// `status`/`retryCount`/`lastError` stay around as diagnostics, not as
    /// a terminal "never again" state.
    ///
    /// Re-pulls once more at the end if this pass flagged a new conflict —
    /// that conflicted row no longer protects its own content against a
    /// pull (see `queuedTargetLocalIDs`), so this is what actually resyncs
    /// it to the server's real state in the same pass that discovered the
    /// conflict, rather than leaving the discarded local edit on screen
    /// until whatever the next unrelated sync trigger happens to be.
    public func drainProjectMutations() async throws {
        let items = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .project
                        && ($0.status == .pending || $0.status == .failed) && !$0.needsConflictResolution
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
        var flaggedNewConflict = false
        for item in items {
            // Every item must still be drained regardless of outcome, so
            // this can't be a `where` filter.
            // swiftlint:disable:next for_where
            if await drain(item) == .conflicted {
                flaggedNewConflict = true
            }
        }
        if flaggedNewConflict {
            try? await pullProjects()
        }
    }

    enum DrainOutcome {
        case pushed
        case deferred
        case conflicted
        case skipped
    }

    private func drain(_ item: MutationQueueRecord) async -> DrainOutcome {
        do {
            switch item.operation {
            case .create: return try await drainCreate(item)
            case .update: return try await drainUpdate(item)
            case .delete: return try await drainDelete(item)
            case .addLabel, .removeLabel, .addRelation, .removeRelation:
                // Only ever queued against `entityType: .task` - unreachable
                // here since `drainProjectMutations()` filters to `.project`.
                return .skipped
            }
        } catch {
            await markFailed(item, error: error)
            return .skipped
        }
    }

    private func drainCreate(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let payload: ProjectCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let resolvedParentID = try await localStore.read { db in
            try Self.resolveRemoteID(forLocalID: payload.parentProjectLocalID, db: db)
        }
        guard payload.parentProjectLocalID == nil || resolvedParentID != nil else {
            return .deferred // The parent hasn't synced yet — retry this item on a later pass.
        }
        let project = Project(
            id: .local(item.targetLocalID),
            title: payload.title,
            description: payload.description,
            isArchived: payload.isArchived,
            isFavorite: payload.isFavorite,
            parentProjectID: resolvedParentID.map(EntityID.remote),
            position: payload.position,
            hexColor: payload.hexColor,
        )
        let created = try await projectRepository.create(project)
        try await applyPushResult(created, deleting: item)
        return .pushed
    }

    private func drainUpdate(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let payload: ProjectCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let (currentRow, resolvedParentID) = try await localStore.read { db in
            let row = try ProjectRecord.fetchOne(db, key: item.targetLocalID)
            let parentID = try Self.resolveRemoteID(forLocalID: payload.parentProjectLocalID, db: db)
            return (row, parentID)
        }
        guard let currentRow, let remoteID = currentRow.remoteID else {
            return .skipped // Not synced yet — there's nothing server-side to update.
        }
        guard payload.parentProjectLocalID == nil || resolvedParentID != nil else {
            return .deferred // The new parent hasn't synced yet — retry this item on a later pass.
        }
        if let baseUpdatedAt = payload.baseUpdatedAt, let serverUpdatedAt = currentRow.serverUpdatedAt,
           serverUpdatedAt.timeIntervalSince(baseUpdatedAt) > 1 {
            try await flagConflict(item)
            return .conflicted
        }
        let project = Project(
            id: .remote(remoteID),
            title: payload.title,
            description: payload.description,
            isArchived: payload.isArchived,
            isFavorite: payload.isFavorite,
            parentProjectID: resolvedParentID.map(EntityID.remote),
            position: payload.position,
            hexColor: payload.hexColor,
        )
        let updated = try await projectRepository.update(project)
        try await applyPushResult(updated, deleting: item)
        return .pushed
    }

    private func drainDelete(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let payload: ProjectDeletePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        try await projectRepository.delete(id: .remote(payload.remoteID))
        try await localStore.write { db in
            if let row = try ProjectRecord.fetchOne(db, key: item.targetLocalID) {
                try row.delete(db)
            }
            try item.delete(db)
        }
        return .pushed
    }

    /// Persists a successful `create`/`update`'s server response and
    /// removes the drained queue item. Shared because the two operations'
    /// post-success bookkeeping is otherwise identical — `create` is simply
    /// the case where `remoteID` was `nil` beforehand.
    private func applyPushResult(_ project: Project, deleting item: MutationQueueRecord) async throws {
        guard let remoteID = project.id.remoteValue else {
            preconditionFailure("SyncEngine: a pushed create/update's response must carry a resolved remote id")
        }
        try await localStore.write { db in
            if var row = try ProjectRecord.fetchOne(db, key: item.targetLocalID) {
                row.remoteID = remoteID
                row.serverUpdatedAt = project.updated
                try row.save(db)
            } else if item.operation == .create {
                try Self.enqueueCompensatingDelete(item, remoteID: remoteID, db: db)
            }
            try Self.completePush(item, updatedAt: project.updated, db: db)
        }
    }

    // MARK: - Draining saved-filter mutations

    /// Saved filters use `/filters` for writes but share their local
    /// presentation row with the `/projects` pseudo-project. A delete keeps
    /// that row (hidden by `OfflineProjectRepository`) until the server has
    /// confirmed it, so a failed request remains retryable and inspectable.
    public func drainFilterMutations() async throws {
        guard let filterRepository else { return }
        let items = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .filter
                        && ($0.status == .pending || $0.status == .failed)
                        && !$0.needsConflictResolution
                }
                .sorted { $0.createdAt < $1.createdAt }
        }

        for item in items {
            do {
                switch item.operation {
                case .update:
                    guard let payload: FilterRenamePayload = try decodePayload(item.payload) else {
                        throw DrainError.invalidPayload
                    }
                    _ = try await filterRepository.renameFilter(id: payload.remoteID, title: payload.title)
                    try await localStore.write { db in
                        guard let currentItem = try MutationQueueRecord.fetchOne(db, key: item.id),
                              currentItem.payload == item.payload
                        else { return }
                        if var project = try ProjectRecord.fetchOne(db, key: item.targetLocalID) {
                            project.title = payload.title
                            try project.save(db)
                        }
                        try item.delete(db)
                    }
                case .delete:
                    guard let payload: FilterDeletePayload = try decodePayload(item.payload) else {
                        throw DrainError.invalidPayload
                    }
                    try await filterRepository.deleteFilter(id: payload.remoteID)
                    try await localStore.write { db in
                        guard let currentItem = try MutationQueueRecord.fetchOne(db, key: item.id),
                              currentItem.payload == item.payload
                        else { return }
                        if let project = try ProjectRecord.fetchOne(db, key: item.targetLocalID) {
                            try project.delete(db)
                        }
                        try item.delete(db)
                    }
                case .create, .addLabel, .removeLabel, .addRelation, .removeRelation:
                    throw DrainError.invalidPayload
                }
            } catch {
                await markFilterMutationFailed(item, error: error)
            }
        }
    }

    /// A user can replace an in-flight rename with a newer title or a delete
    /// while its request is suspended. Only mark the exact queued snapshot
    /// that failed; otherwise an old response could fail or delete newer work.
    private func markFilterMutationFailed(_ item: MutationQueueRecord, error: Error) async {
        try? await localStore.write { db in
            guard var currentItem = try MutationQueueRecord.fetchOne(db, key: item.id),
                  currentItem.entityType == .filter,
                  currentItem.targetLocalID == item.targetLocalID,
                  currentItem.operation == item.operation,
                  currentItem.payload == item.payload
            else { return }
            currentItem.retryCount += 1
            currentItem.lastError = String(describing: error)
            currentItem.status = .failed
            try currentItem.update(db)
        }
    }

    // MARK: - Draining label mutations

    /// Same shape as `drainProjectMutations()`, minus the conflict re-pull:
    /// a label mutation never gets flagged `.conflicted` in the first place
    /// (see `LabelCreateOrUpdatePayload`), so there's nothing here that
    /// would ever need one.
    public func drainLabelMutations() async throws {
        let items = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .label
                        && ($0.status == .pending || $0.status == .failed) && !$0.needsConflictResolution
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
        for item in items {
            await drainLabel(item)
        }
    }

    private func drainLabel(_ item: MutationQueueRecord) async {
        do {
            switch item.operation {
            case .create: try await drainLabelCreate(item)
            case .update: try await drainLabelUpdate(item)
            case .delete: try await drainLabelDelete(item)
            case .addLabel, .removeLabel, .addRelation, .removeRelation:
                // Only ever queued against `entityType: .task` - unreachable
                // here since `drainLabelMutations()` filters to `.label`.
                break
            }
        } catch {
            await markFailed(item, error: error)
        }
    }

    private func drainLabelCreate(_ item: MutationQueueRecord) async throws {
        guard let payload: LabelCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let label = Label(id: .local(item.targetLocalID), title: payload.title, hexColor: payload.hexColor)
        let created = try await labelRepository.create(label)
        try await applyLabelPushResult(created, deleting: item)
    }

    private func drainLabelUpdate(_ item: MutationQueueRecord) async throws {
        guard let payload: LabelCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let currentRow = try await localStore.read { db in try LabelRecord.fetchOne(db, key: item.targetLocalID) }
        guard let currentRow, let remoteID = currentRow.remoteID else {
            return // Not synced yet — there's nothing server-side to update.
        }
        let label = Label(id: .remote(remoteID), title: payload.title, hexColor: payload.hexColor)
        let updated = try await labelRepository.update(label)
        try await applyLabelPushResult(updated, deleting: item)
    }

    private func drainLabelDelete(_ item: MutationQueueRecord) async throws {
        guard let payload: LabelDeletePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        try await labelRepository.delete(id: .remote(payload.remoteID))
        try await localStore.write { db in
            if let row = try LabelRecord.fetchOne(db, key: item.targetLocalID) {
                try row.delete(db)
            }
            try item.delete(db)
        }
    }

    private func applyLabelPushResult(_ label: Label, deleting item: MutationQueueRecord) async throws {
        guard let remoteID = label.id.remoteValue else {
            preconditionFailure("SyncEngine: a pushed label create/update's response must carry a resolved remote id")
        }
        try await localStore.write { db in
            if var row = try LabelRecord.fetchOne(db, key: item.targetLocalID) {
                row.remoteID = remoteID
                try row.save(db)
            } else if item.operation == .create {
                try Self.enqueueCompensatingDelete(item, remoteID: remoteID, db: db)
            }
            try Self.completePush(item, updatedAt: nil, db: db)
        }
    }

    // MARK: - Draining task mutations

    /// Same shape as `drainProjectMutations()`, including the conflict
    /// re-pull: a task mutation can be flagged `.conflicted` in
    /// `drainTaskUpdate`, exactly like a project's.
    public func drainTaskMutations() async throws {
        try await recoverKanbanCreations()
        let items = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .task
                        && ($0.status == .pending || $0.status == .failed) && !$0.needsConflictResolution
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
        var flaggedNewConflict = false
        for item in items {
            // Every item must still be drained regardless of outcome, so
            // this can't be a `where` filter.
            // swiftlint:disable:next for_where
            if await drainTask(item) == .conflicted {
                flaggedNewConflict = true
            }
        }
        if flaggedNewConflict {
            try? await pullTasks()
        }
    }

    private func drainTask(_ item: MutationQueueRecord) async -> DrainOutcome {
        do {
            switch item.operation {
            case .create: return try await drainTaskCreate(item)
            case .update: return try await drainTaskUpdate(item)
            case .delete: return try await drainTaskDelete(item)
            case .addLabel: return try await drainTaskLabelMutation(item, isAdding: true)
            case .removeLabel: return try await drainTaskLabelMutation(item, isAdding: false)
            case .addRelation: return try await drainTaskRelationMutation(item, isAdding: true)
            case .removeRelation: return try await drainTaskRelationMutation(item, isAdding: false)
            }
        } catch {
            await markFailed(item, error: error)
            return .skipped
        }
    }

    // MARK: - Draining comment mutations

    /// Replays every queued comment create/update/delete, oldest first. Same
    /// `.failed`-items-retry and one-failure-doesn't-stop-the-rest behavior
    /// as every other drain. A create queued against a task that hasn't
    /// synced yet is deferred until a later pass, exactly like a task
    /// referencing an unsynced project.
    public func drainCommentMutations() async throws {
        guard let commentRepository else { return }
        let items = try await localStore.read { db in
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.entityType == .comment
                        && ($0.status == .pending || $0.status == .failed) && !$0.needsConflictResolution
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
        for item in items {
            _ = await drainComment(item, repository: commentRepository)
        }
    }

    private func drainComment(
        _ item: MutationQueueRecord, repository: TaskCommentRepositoryProtocol,
    ) async -> DrainOutcome {
        do {
            switch item.operation {
            case .create: return try await drainCommentCreate(item, repository: repository)
            case .update: return try await drainCommentUpdate(item, repository: repository)
            case .delete: return try await drainCommentDelete(item, repository: repository)
            case .addLabel, .removeLabel, .addRelation, .removeRelation:
                // Comment rows only ever queue create/update/delete.
                return .skipped
            }
        } catch {
            await markFailed(item, error: error)
            return .skipped
        }
    }

    private func drainCommentCreate(
        _ item: MutationQueueRecord, repository: TaskCommentRepositoryProtocol,
    ) async throws -> DrainOutcome {
        guard let payload: TaskCommentCreatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let taskRemoteID = try await localStore.read { db in
            try TaskRecord.fetchOne(db, key: payload.taskLocalID)?.remoteID
        }
        guard let taskRemoteID else {
            return .deferred // The task hasn't synced yet — retry this item on a later pass.
        }
        let created = try await repository.addComment(payload.text, toTask: .remote(taskRemoteID))
        try await applyCommentPushResult(created, deleting: item)
        return .pushed
    }

    private func drainCommentUpdate(
        _ item: MutationQueueRecord, repository: TaskCommentRepositoryProtocol,
    ) async throws -> DrainOutcome {
        guard let payload: TaskCommentUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let (taskRemoteID, commentRemoteID) = try await localStore.read { db in
            let taskRemoteID = try TaskRecord.fetchOne(db, key: payload.taskLocalID)?.remoteID
            let commentRemoteID = try TaskCommentRecord.fetchOne(db, key: item.targetLocalID)?.remoteID
            return (taskRemoteID, commentRemoteID)
        }
        guard let taskRemoteID, let commentRemoteID else {
            return .deferred // The task or comment hasn't synced yet.
        }
        let updated = try await repository.updateComment(
            .remote(commentRemoteID), text: payload.text, onTask: .remote(taskRemoteID),
        )
        try await applyCommentPushResult(updated, deleting: item)
        return .pushed
    }

    private func drainCommentDelete(
        _ item: MutationQueueRecord, repository: TaskCommentRepositoryProtocol,
    ) async throws -> DrainOutcome {
        guard let payload: TaskCommentDeletePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let taskRemoteID = try await localStore.read { db in
            try TaskRecord.fetchOne(db, key: payload.taskLocalID)?.remoteID
        }
        guard let taskRemoteID else {
            return .deferred // The task hasn't synced yet.
        }
        try await repository.deleteComment(.remote(payload.remoteID), fromTask: .remote(taskRemoteID))
        try await localStore.write { db in
            if let row = try TaskCommentRecord.fetchOne(db, key: item.targetLocalID) {
                try row.delete(db)
            }
            try item.delete(db)
        }
        return .pushed
    }

    private func applyCommentPushResult(
        _ comment: TaskComment, deleting item: MutationQueueRecord,
    ) async throws {
        guard let remoteID = comment.id.remoteValue else {
            preconditionFailure("SyncEngine: a pushed comment create/update's response must carry a resolved remote id")
        }
        try await localStore.write { db in
            guard var row = try TaskCommentRecord.fetchOne(db, key: item.targetLocalID) else {
                if item.operation == .create {
                    try Self.enqueueCompensatingDelete(item, remoteID: remoteID, db: db)
                }
                try Self.completePush(item, updatedAt: comment.updated, db: db)
                return
            }
            row.remoteID = remoteID
            if try MutationQueueRecord.fetchOne(db, key: item.id)?.payload == item.payload {
                row.comment = comment.comment
            }
            row.authorID = comment.author.id
            row.authorUsername = comment.author.username
            row.authorName = comment.author.name
            row.authorEmail = comment.author.email
            row.created = comment.created
            row.updated = comment.updated
            try row.save(db)
            try Self.completePush(item, updatedAt: comment.updated, db: db)
        }
    }

    private func drainTaskCreate(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let payload: TaskCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let resolvedProjectID = try await localStore.read { db in
            try Self.resolveRemoteID(forLocalID: payload.projectLocalID, db: db)
        }
        guard let resolvedProjectID else {
            return .deferred // The project hasn't synced yet — retry this item on a later pass.
        }
        let task = VikunjaTask(
            id: .local(item.targetLocalID),
            title: payload.title,
            description: payload.description,
            isDone: payload.isDone,
            dueDate: payload.dueDate,
            priority: VikunjaTask.Priority(rawValue: payload.priority) ?? .unset,
            projectID: .remote(resolvedProjectID),
            reminders: payload.reminders ?? [],
        )
        if let destination = payload.kanbanDestination {
            return try await drainKanbanCreation(item, task: task, destination: destination)
        }
        let created = try await taskRepository.create(task)
        try await applyTaskPushResult(created, deleting: item)
        return .pushed
    }

    private func drainTaskUpdate(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let payload: TaskCreateOrUpdatePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let (currentRow, resolvedProjectID) = try await localStore.read { db in
            let row = try TaskRecord.fetchOne(db, key: item.targetLocalID)
            let projectID = try Self.resolveRemoteID(forLocalID: payload.projectLocalID, db: db)
            return (row, projectID)
        }
        guard let currentRow, let remoteID = currentRow.remoteID else {
            return .skipped // Not synced yet — there's nothing server-side to update.
        }
        guard let resolvedProjectID else {
            return .deferred // The new project hasn't synced yet — retry this item on a later pass.
        }
        if let baseUpdatedAt = payload.baseUpdatedAt, let serverUpdatedAt = currentRow.serverUpdatedAt,
           serverUpdatedAt.timeIntervalSince(baseUpdatedAt) > 1 {
            try await flagConflict(item)
            return .conflicted
        }
        let task = VikunjaTask(
            id: .remote(remoteID),
            title: payload.title,
            description: payload.description,
            isDone: payload.isDone,
            dueDate: payload.dueDate,
            priority: VikunjaTask.Priority(rawValue: payload.priority) ?? .unset,
            projectID: .remote(resolvedProjectID),
            reminders: payload.reminders ?? [],
        )
        let updated = try await taskRepository.update(task)
        try await applyTaskPushResult(updated, deleting: item)
        return .pushed
    }

    private func drainTaskDelete(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let payload: TaskDeletePayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        try await taskRepository.delete(id: .remote(payload.remoteID))
        try await localStore.write { db in
            if let row = try TaskRecord.fetchOne(db, key: item.targetLocalID) {
                try row.delete(db)
            }
            try item.delete(db)
        }
        return .pushed
    }

    /// `addLabel`/`removeLabel` queued against `targetLocalID` (the task),
    /// with `payload.labelLocalID` identifying the label - mirrors
    /// `drainTaskCreate`'s `payload.projectLocalID` dependency-ordering:
    /// either side still only local-so-far simply defers this item to the
    /// next drain pass instead of failing it.
    private func drainTaskLabelMutation(_ item: MutationQueueRecord, isAdding: Bool) async throws -> DrainOutcome {
        guard let payload: TaskLabelMutationPayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        let (taskRemoteID, labelRemoteID) = try await localStore.read { db in
            let taskRemoteID = try TaskRecord.fetchOne(db, key: item.targetLocalID)?.remoteID
            let labelRemoteID = try LabelRecord.fetchOne(db, key: payload.labelLocalID)?.remoteID
            return (taskRemoteID, labelRemoteID)
        }
        guard let taskRemoteID, let labelRemoteID else {
            return .deferred // The task or label hasn't synced yet — retry this item on a later pass.
        }
        if isAdding {
            try await labelRepository.addLabel(.remote(labelRemoteID), toTask: .remote(taskRemoteID))
        } else {
            try await labelRepository.removeLabel(.remote(labelRemoteID), fromTask: .remote(taskRemoteID))
        }
        try await localStore.write { db in
            if var row = try TaskRecord.fetchOne(db, key: item.targetLocalID) {
                // The push just made this true server-side, but every screen
                // reads a task's labels from this cache (see its doc
                // comment), which otherwise only catches up on the next
                // `pullTasks()` — patch it now instead of leaving it stale
                // until then.
                var ids = row.labelRemoteIDs.split(separator: ",").compactMap { Int($0) }
                if isAdding {
                    if !ids.contains(labelRemoteID) {
                        ids.append(labelRemoteID)
                    }
                } else {
                    ids.removeAll { $0 == labelRemoteID }
                }
                row.labelRemoteIDs = ids.map(String.init).joined(separator: ",")
                try row.save(db)
            }
            try item.delete(db)
        }
        return .pushed
    }

    /// `addRelation`/`removeRelation` queued against `targetLocalID` (the
    /// task), with `payload.otherTaskLocalID`/`payload.kind` identifying the
    /// other side - mirrors `drainTaskLabelMutation`'s dependency-ordering,
    /// except both the task *and* the other task can still be only
    /// local-so-far (a relation can be queued between two tasks both
    /// created offline), so both are resolved here, not just one.
    private func drainTaskRelationMutation(_ item: MutationQueueRecord, isAdding: Bool) async throws -> DrainOutcome {
        guard let payload: TaskRelationMutationPayload = try decodePayload(item.payload) else {
            throw DrainError.invalidPayload
        }
        guard let resolved = try await localStore.read({ db in
            try Self.resolveRelationMutationRows(
                taskLocalID: item.targetLocalID, otherTaskLocalID: payload.otherTaskLocalID, db: db,
            )
        }) else {
            return .deferred // The task, the other task, or either's project hasn't synced yet.
        }
        if isAdding {
            try await relationRepository.addRelation(
                kind: payload.kind, otherTaskID: .remote(resolved.otherTaskRemoteID),
                toTask: .remote(resolved.taskRemoteID),
            )
        } else {
            try await relationRepository.removeRelation(
                kind: payload.kind, otherTaskID: .remote(resolved.otherTaskRemoteID),
                fromTask: .remote(resolved.taskRemoteID),
            )
        }
        try await localStore.write { db in
            try Self.patchRelationCache(
                isAdding: isAdding, kind: payload.kind, taskLocalID: item.targetLocalID,
                otherTaskLocalID: payload.otherTaskLocalID, resolved: resolved, accountID: self.accountID, db: db,
            )
            try item.delete(db)
        }
        return .pushed
    }

    private struct ResolvedRelationMutation {
        let taskRemoteID: Int
        let taskProjectRemoteID: Int
        let taskTitle: String
        let taskIsDone: Bool
        let otherTaskRemoteID: Int
        let otherProjectRemoteID: Int
        let otherTitle: String
        let otherIsDone: Bool
    }

    private static func resolveRelationMutationRows(
        taskLocalID: UUID, otherTaskLocalID: UUID, db: Database,
    ) throws -> ResolvedRelationMutation? {
        guard let taskRow = try TaskRecord.fetchOne(db, key: taskLocalID), let taskRemoteID = taskRow.remoteID,
              let otherTaskRow = try TaskRecord.fetchOne(db, key: otherTaskLocalID),
              let otherTaskRemoteID = otherTaskRow.remoteID,
              let taskProjectRemoteID = try ProjectRecord.fetchOne(db, key: taskRow.projectLocalID)?.remoteID,
              let otherProjectRemoteID = try ProjectRecord.fetchOne(db, key: otherTaskRow.projectLocalID)?.remoteID
        else {
            return nil
        }
        return ResolvedRelationMutation(
            taskRemoteID: taskRemoteID, taskProjectRemoteID: taskProjectRemoteID, taskTitle: taskRow.title,
            taskIsDone: taskRow.isDone, otherTaskRemoteID: otherTaskRemoteID,
            otherProjectRemoteID: otherProjectRemoteID, otherTitle: otherTaskRow.title,
            otherIsDone: otherTaskRow.isDone,
        )
    }

    // swiftlint:disable function_parameter_count
    /// Patches the `taskRelation` cache on both sides of a successful push —
    /// the push just made this true server-side, but every screen reads a
    /// task's relations from this cache (see `TaskRelationRecord`'s doc
    /// comment), which otherwise only catches up on the next `pullTasks()`.
    /// Both sides because Vikunja's relations are bidirectional under
    /// paired kinds (`subtask`/`parenttask`, `blocking`/`blocked`, ...) -
    /// without this, the other task's own relation list would show nothing
    /// until its own next pull. Deletes any existing match before inserting
    /// rather than a blind insert, so a retry after a response that
    /// succeeded server-side but was lost locally can't violate the unique
    /// index.
    private static func patchRelationCache(
        isAdding: Bool, kind: RelationKind, taskLocalID: UUID, otherTaskLocalID: UUID,
        resolved: ResolvedRelationMutation, accountID: UUID, db: Database,
    ) throws {
        let inverseKind = Self.inverseKind(kind)
        try TaskRelationRecord
            .filter(Column("taskLocalID") == taskLocalID && Column("kind") == kind.rawValue
                && Column("otherTaskRemoteID") == resolved.otherTaskRemoteID)
            .deleteAll(db)
        try TaskRelationRecord
            .filter(Column("taskLocalID") == otherTaskLocalID && Column("kind") == inverseKind.rawValue
                && Column("otherTaskRemoteID") == resolved.taskRemoteID)
            .deleteAll(db)
        guard isAdding else { return }
        let forward = TaskRelationRecord(
            localID: UUID(), accountID: accountID, taskLocalID: taskLocalID, kind: kind,
            otherTaskRemoteID: resolved.otherTaskRemoteID, otherProjectRemoteID: resolved.otherProjectRemoteID,
            title: resolved.otherTitle, isDone: resolved.otherIsDone,
        )
        try forward.insert(db)
        let mirror = TaskRelationRecord(
            localID: UUID(), accountID: accountID, taskLocalID: otherTaskLocalID, kind: inverseKind,
            otherTaskRemoteID: resolved.taskRemoteID, otherProjectRemoteID: resolved.taskProjectRemoteID,
            title: resolved.taskTitle, isDone: resolved.taskIsDone,
        )
        try mirror.insert(db)
    }

    // swiftlint:enable function_parameter_count

    /// The relation kind the other side of a pair sees once this one is
    /// created — e.g. A's `subtask` B implies B's `parenttask` A. `related`
    /// is its own inverse (Vikunja doesn't distinguish direction for it).
    private static func inverseKind(_ kind: RelationKind) -> RelationKind {
        switch kind {
        case .subtask: .parenttask
        case .parenttask: .subtask
        case .blocking: .blocked
        case .blocked: .blocking
        case .duplicateof: .duplicates
        case .duplicates: .duplicateof
        case .precedes: .follows
        case .follows: .precedes
        case .copiedfrom: .copiedto
        case .copiedto: .copiedfrom
        case .related: .related
        }
    }

    func applyTaskPushResult(_ task: VikunjaTask, deleting item: MutationQueueRecord) async throws {
        guard let remoteID = task.id.remoteValue else {
            preconditionFailure("SyncEngine: a pushed task create/update's response must carry a resolved remote id")
        }
        try await localStore.write { db in
            if var row = try TaskRecord.fetchOne(db, key: item.targetLocalID) {
                row.remoteID = remoteID
                row.serverUpdatedAt = task.updated
                try row.save(db)
            } else if item.operation == .create {
                try Self.enqueueCompensatingDelete(item, remoteID: remoteID, db: db)
            }
            if try MutationQueueRecord.fetchOne(db, key: item.id)?.payload == item.payload,
               try TaskRecord.fetchOne(db, key: item.targetLocalID) != nil {
                try TaskReminderRecord.replace(
                    for: item.targetLocalID, accountID: self.accountID, reminders: task.reminders, db: db,
                )
            }
            try Self.completePush(item, updatedAt: task.updated, db: db)
        }
    }

    /// An edit can coalesce into a queue row while its earlier payload is
    /// awaiting the server. Preserve that newer intent and rebase it on our
    /// own successful response; a completed create becomes an update.
    private static func completePush(_ sent: MutationQueueRecord, updatedAt: Date?, db: Database) throws {
        guard var current = try MutationQueueRecord.fetchOne(db, key: sent.id) else { return }
        guard current.payload != sent.payload || current.operation != sent.operation else {
            try current.delete(db)
            return
        }
        if current.operation == .create {
            current.operation = .update
        }
        if current.entityType == .project,
           var payload = try decode(ProjectCreateOrUpdatePayload.self, from: current.payload) {
            payload.baseUpdatedAt = updatedAt
            current.payload = try encodePayload(payload)
        }
        if current.entityType == .task,
           var payload = try decode(TaskCreateOrUpdatePayload.self, from: current.payload) {
            payload.baseUpdatedAt = updatedAt
            current.payload = try encodePayload(payload)
        }
        current.needsConflictResolution = false
        current.baseUpdatedAt = updatedAt
        current.status = .pending
        current.lastError = nil
        current.retryCount = 0
        try current.update(db)
    }

    /// A local-only row can be deleted while its create is in flight. Keep a
    /// durable delete for the newly assigned server id, rather than leaving
    /// a remote object the user already removed locally.
    private static func enqueueCompensatingDelete(_ sent: MutationQueueRecord, remoteID: Int, db: Database) throws {
        let payload: String
        switch sent.entityType {
        case .project: payload = try encodePayload(ProjectDeletePayload(remoteID: remoteID))
        case .label: payload = try encodePayload(LabelDeletePayload(remoteID: remoteID))
        case .task: payload = try encodePayload(TaskDeletePayload(remoteID: remoteID))
        case .comment:
            guard let created = try decode(TaskCommentCreatePayload.self, from: sent.payload) else { return }
            payload = try encodePayload(TaskCommentDeletePayload(taskLocalID: created.taskLocalID, remoteID: remoteID))
        case .filter: return
        }
        var deletion = MutationQueueRecord(
            id: nil, accountID: sent.accountID, entityType: sent.entityType, operation: .delete,
            targetLocalID: sent.targetLocalID, payload: payload, createdAt: Date(), retryCount: 0,
            lastError: nil, status: .pending, needsConflictResolution: false,
        )
        try deletion.insert(db)
    }

    private static func encodePayload(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try String(bytes: encoder.encode(payload), encoding: .utf8) else {
            throw DrainError.invalidPayload
        }
        return encoded
    }

    private func flagConflict(_ item: MutationQueueRecord) async throws {
        try await localStore.write { db in
            guard var row = try MutationQueueRecord.fetchOne(db, key: item.id),
                  row.payload == item.payload else { return }
            row.needsConflictResolution = true
            try row.update(db)
        }
    }

    private func markFailed(_ item: MutationQueueRecord, error: Error) async {
        try? await localStore.write { db in
            guard var row = try MutationQueueRecord.fetchOne(db, key: item.id),
                  row.payload == item.payload else { return }
            row.retryCount += 1
            row.lastError = String(describing: error)
            row.status = .failed
            try row.update(db)
        }
    }

    private static func resolveRemoteID(forLocalID localID: UUID?, db: Database) throws -> Int? {
        guard let localID else { return nil }
        return try ProjectRecord.fetchOne(db, key: localID)?.remoteID
    }

    private func decodePayload<T: Decodable>(_ payload: String?) throws -> T? {
        try Self.decode(T.self, from: payload)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from payload: String?) throws -> T? {
        guard let payload, let data = payload.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

/// The remote reads may succeed while queued uploads fail or need conflict
/// resolution. Never report such a pass as a fully successful refresh.
private struct SyncIncompleteError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Some changes could not be synced. Check Pending Sync in Settings.", bundle: .module)
    }
}
