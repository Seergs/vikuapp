import Foundation
import GRDB
import VikunjaCore

/// Keeps one account's slice of the local store's cache in step with the
/// server: pulls the server's state in, and drains that account's locally
/// queued mutations back out.
public actor SyncEngine {
    private let localStore: LocalStore
    private let projectRepository: ProjectRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let taskRepository: TaskRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    /// `nil` in tests/constructions that never touch comments. Every real
    /// `SyncEngine` built by the app or `SyncCoordinator` passes one.
    private let commentRepository: TaskCommentRepositoryProtocol?
    /// `InstanceAccount.id` — every row this engine reads or writes is
    /// scoped to this one account, since `LocalStore`'s tables hold every
    /// saved account's data together rather than one database file each.
    private let accountID: UUID

    public init(
        localStore: LocalStore,
        projectRepository: ProjectRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        taskRepository: TaskRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        commentRepository: TaskCommentRepositoryProtocol? = nil,
        accountID: UUID,
    ) {
        self.localStore = localStore
        self.projectRepository = projectRepository
        self.labelRepository = labelRepository
        self.taskRepository = taskRepository
        self.relationRepository = relationRepository
        self.commentRepository = commentRepository
        self.accountID = accountID
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
        let remoteProjects = try await projectRepository.fetchProjects()
        let now = Date()

        try await localStore.write { db in
            let localRows = try ProjectRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            let localIDByRemoteID = Self.reserveLocalIDs(for: remoteProjects, existing: localRows)
            let queuedTargetLocalIDs = try Self.queuedTargetLocalIDs(
                accountID: self.accountID, entityType: .project, db: db,
            )

            try Self.upsertRows(
                for: remoteProjects, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
            )
            try Self.resolveParentLinks(
                for: remoteProjects, localIDByRemoteID: localIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
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
    private static func reserveLocalIDs(for remoteProjects: [Project], existing localRows: [ProjectRecord]) -> [Int: UUID] {
        var localIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: localRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        for project in remoteProjects {
            guard let remoteID = project.id.remoteValue, localIDByRemoteID[remoteID] == nil else { continue }
            localIDByRemoteID[remoteID] = UUID()
        }
        return localIDByRemoteID
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
        let remoteLabels = try await labelRepository.fetchLabels()
        let now = Date()

        try await localStore.write { db in
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

    private static func reserveLabelLocalIDs(for remoteLabels: [Label], existing localRows: [LabelRecord]) -> [Int: UUID] {
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

    /// Fetches every task across every real (non-virtual), already-synced
    /// project and reconciles it into the local store — same shape as
    /// `pullProjects()`, including its conflict-detection refresh, but with
    /// no separate FK-resolution pass: unlike a sub-project's parent (which
    /// can reference a project appearing later in the same response), each
    /// task's project is already known the moment its own fetch is issued
    /// (`fetchTasks(projectID:)` is itself scoped to one project), so
    /// `projectLocalID` is set directly in `upsertTaskRows`.
    ///
    /// Reads the already-pulled local project list rather than calling
    /// `projectRepository.fetchProjects()` again — `pullProjects()` always
    /// runs first in `SyncCoordinator.sync(_:)`, and reusing its result
    /// avoids a second network round trip for the same data. Mirrors
    /// `AccountTaskLoader.loadAllTasks()`'s own "skip virtual projects"
    /// behavior, but only reconciles a project whose fetch actually
    /// succeeded: treating a failed fetch as an empty one used to delete
    /// every cached task for that project, so a single offline sync pass
    /// could wipe the local task list.
    public func pullTasks() async throws {
        let now = Date()
        let projectRows = try await localStore.read { db in
            try ProjectRecord.fetchAll(db).filter { $0.accountID == self.accountID }
        }

        var remoteTasks: [VikunjaTask] = []
        var fetchedProjectLocalIDs: Set<UUID> = []
        var firstError: (any Error)?
        for projectRow in projectRows {
            // A negative or zero remote id is a virtual project (Favorites,
            // a saved filter) — its "tasks" are just a view over tasks that
            // already live in a real project, so fetching them would double
            // every such task. A project with no remote id yet (offline-
            // created) can't have any tasks on the server yet either.
            guard let remoteProjectID = projectRow.remoteID, remoteProjectID > 0 else { continue }
            do {
                remoteTasks += try await taskRepository.fetchTasks(projectID: .remote(remoteProjectID))
                fetchedProjectLocalIDs.insert(projectRow.localID)
            } catch {
                firstError = firstError ?? error
            }
        }

        let projectLocalIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: projectRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        let fetchedTasks = remoteTasks
        let reconciledProjectLocalIDs = fetchedProjectLocalIDs
        let didCompleteWithoutErrors = firstError == nil

        try await localStore.write { db in
            let localRows = try TaskRecord.fetchAll(db).filter { $0.accountID == self.accountID }
            let localIDByRemoteID = Self.reserveTaskLocalIDs(for: fetchedTasks, existing: localRows)
            let queuedTargetLocalIDs = try Self.queuedTargetLocalIDs(
                accountID: self.accountID, entityType: .task, db: db,
            )

            try Self.upsertTaskRows(
                for: fetchedTasks, accountID: self.accountID, localIDByRemoteID: localIDByRemoteID,
                projectLocalIDByRemoteID: projectLocalIDByRemoteID,
                protectedLocalIDs: queuedTargetLocalIDs, db: db,
            )
            try Self.deleteMissingTaskRows(
                localRows.filter { reconciledProjectLocalIDs.contains($0.projectLocalID) },
                stillPresentRemoteIDs: Set(fetchedTasks.compactMap(\.id.remoteValue)),
                protectedLocalIDs: queuedTargetLocalIDs,
                db: db,
            )

            if didCompleteWithoutErrors {
                try SyncStateRecord(accountID: self.accountID, entityType: .task, lastPulledAt: now).save(db)
            }
        }

        if let firstError {
            throw firstError
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

    private static func reserveTaskLocalIDs(for remoteTasks: [VikunjaTask], existing localRows: [TaskRecord]) -> [Int: UUID] {
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
    private static func replaceRelationRows(for localID: UUID, accountID: UUID, task: VikunjaTask, db: Database) throws {
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

    private enum DrainOutcome {
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
            }
            try item.delete(db)
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
            }
            try item.delete(db)
        }
    }

    // MARK: - Draining task mutations

    /// Same shape as `drainProjectMutations()`, including the conflict
    /// re-pull: a task mutation can be flagged `.conflicted` in
    /// `drainTaskUpdate`, exactly like a project's.
    public func drainTaskMutations() async throws {
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
                try item.delete(db)
                return
            }
            row.remoteID = remoteID
            row.comment = comment.comment
            row.authorID = comment.author.id
            row.authorUsername = comment.author.username
            row.authorName = comment.author.name
            row.authorEmail = comment.author.email
            row.created = comment.created
            row.updated = comment.updated
            try row.save(db)
            try item.delete(db)
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

    private func applyTaskPushResult(_ task: VikunjaTask, deleting item: MutationQueueRecord) async throws {
        guard let remoteID = task.id.remoteValue else {
            preconditionFailure("SyncEngine: a pushed task create/update's response must carry a resolved remote id")
        }
        try await localStore.write { db in
            if var row = try TaskRecord.fetchOne(db, key: item.targetLocalID) {
                row.remoteID = remoteID
                row.serverUpdatedAt = task.updated
                try row.save(db)
            }
            try TaskReminderRecord.replace(
                for: item.targetLocalID, accountID: self.accountID, reminders: task.reminders, db: db,
            )
            try item.delete(db)
        }
    }

    private func flagConflict(_ item: MutationQueueRecord) async throws {
        try await localStore.write { db in
            var row = item
            row.needsConflictResolution = true
            try row.update(db)
        }
    }

    private func markFailed(_ item: MutationQueueRecord, error: Error) async {
        try? await localStore.write { db in
            var row = item
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
