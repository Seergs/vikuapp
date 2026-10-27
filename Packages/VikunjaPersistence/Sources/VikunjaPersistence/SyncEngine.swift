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
    /// `InstanceAccount.id` — every row this engine reads or writes is
    /// scoped to this one account, since `LocalStore`'s tables hold every
    /// saved account's data together rather than one database file each.
    private let accountID: UUID

    public init(
        localStore: LocalStore,
        projectRepository: ProjectRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        taskRepository: TaskRepositoryProtocol,
        accountID: UUID,
    ) {
        self.localStore = localStore
        self.projectRepository = projectRepository
        self.labelRepository = labelRepository
        self.taskRepository = taskRepository
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
    /// `AccountTaskLoader.loadAllTasks()`'s own "skip virtual projects,
    /// tolerate one project's fetch failing" behavior.
    public func pullTasks() async throws {
        let now = Date()
        let projectRows = try await localStore.read { db in
            try ProjectRecord.fetchAll(db).filter { $0.accountID == self.accountID }
        }

        var remoteTasks: [VikunjaTask] = []
        for projectRow in projectRows {
            // A negative or zero remote id is a virtual project (Favorites,
            // a saved filter) — its "tasks" are just a view over tasks that
            // already live in a real project, so fetching them would double
            // every such task. A project with no remote id yet (offline-
            // created) can't have any tasks on the server yet either.
            guard let remoteProjectID = projectRow.remoteID, remoteProjectID > 0 else { continue }
            remoteTasks += await (try? taskRepository.fetchTasks(projectID: .remote(remoteProjectID))) ?? []
        }

        let projectLocalIDByRemoteID: [Int: UUID] = Dictionary(
            uniqueKeysWithValues: projectRows.compactMap { row in row.remoteID.map { ($0, row.localID) } },
        )
        let fetchedTasks = remoteTasks

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
                localRows,
                stillPresentRemoteIDs: Set(fetchedTasks.compactMap(\.id.remoteValue)),
                protectedLocalIDs: queuedTargetLocalIDs,
                db: db,
            )

            try SyncStateRecord(accountID: self.accountID, entityType: .task, lastPulledAt: now).save(db)
        }
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
            try row.save(db)
        }
    }

    // swiftlint:enable function_parameter_count

    private static func deleteMissingTaskRows(
        _ localRows: [TaskRecord],
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
           serverUpdatedAt > baseUpdatedAt {
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
            }
        } catch {
            await markFailed(item, error: error)
            return .skipped
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
           serverUpdatedAt > baseUpdatedAt {
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
        guard let payload, let data = payload.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
