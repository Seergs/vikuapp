import Foundation
import GRDB
import VikunjaCore

/// Local-first saved-filter repository. The linked project row owns the
/// filter's presentation fields; `savedFilter` owns only its query cache.
public actor OfflineFilterRepository: FilterRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let networkRepository: FilterRepositoryProtocol
    private let syncEngine: SyncEngine
    private let reachability: ReachabilityMonitoring

    public init(
        localStore: LocalStore,
        accountID: UUID,
        networkRepository: FilterRepositoryProtocol,
        syncEngine: SyncEngine,
        reachability: ReachabilityMonitoring,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.networkRepository = networkRepository
        self.syncEngine = syncEngine
        self.reachability = reachability
    }

    /// Reads the local snapshot first. When online, refreshes the query from
    /// `/filters`; if that request fails, an already-pulled query remains
    /// usable. A backfilled row with no `lastPulledAt` is not treated as a
    /// valid offline detail because its query has never been downloaded.
    public func fetchFilter(id: Int) async throws -> SavedFilterDetail {
        let cached = try await cachedFilter(id: id)
        if let cached, cached.lastPulledAt != nil {
            if await reachability.isReachable {
                // Return the local detail immediately; refresh for the next
                // read without making a cached screen wait on the network.
                Task { try? await self.refreshQuery(id: id) }
            }
            return cached.detail
        }
        if await reachability.isReachable {
            let remote = try await networkRepository.fetchFilter(id: id)
            return try await storeQuery(remote.query, for: id)
        }
        throw VikunjaError.network("This saved filter's query has not been cached yet.")
    }

    public func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = try await localStore.write { db -> SavedFilterDetail in
            guard let (project, savedFilter) = try Self.rows(for: id, accountID: self.accountID, db: db) else {
                throw VikunjaError.notFound
            }
            let hasPendingDelete = try MutationQueueRecord.fetchAll(db).contains {
                $0.accountID == self.accountID && $0.entityType == .filter
                    && $0.targetLocalID == project.localID && $0.operation == .delete
                    && ($0.status == .pending || $0.status == .failed)
            }
            guard !hasPendingDelete else { throw VikunjaError.notFound }

            var updatedProject = project
            updatedProject.title = trimmedTitle
            try updatedProject.save(db)
            try Self.enqueueRename(
                FilterRenamePayload(remoteID: id, title: trimmedTitle),
                targetLocalID: project.localID,
                accountID: self.accountID,
                db: db,
            )
            return Self.detail(project: updatedProject, savedFilter: savedFilter)
        }
        await drainIfOnline()
        return detail
    }

    public func deleteFilter(id: Int) async throws {
        try await localStore.write { db in
            guard let (project, _) = try Self.rows(for: id, accountID: self.accountID, db: db) else {
                throw VikunjaError.notFound
            }
            let items = try MutationQueueRecord.fetchAll(db).filter {
                $0.accountID == self.accountID && $0.entityType == .filter
                    && $0.targetLocalID == project.localID
                    && ($0.status == .pending || $0.status == .failed)
            }
            if var existingDelete = items.first(where: { $0.operation == .delete }) {
                existingDelete.payload = try Self.encode(FilterDeletePayload(remoteID: id))
                existingDelete.status = .pending
                existingDelete.lastError = nil
                existingDelete.retryCount = 0
                try existingDelete.update(db)
            } else {
                // A delete supersedes any queued rename: there is no value in
                // uploading a title for a filter that is about to disappear.
                for item in items where item.operation == .update {
                    try item.delete(db)
                }
                var item = try MutationQueueRecord(
                    id: nil,
                    accountID: self.accountID,
                    entityType: .filter,
                    operation: .delete,
                    targetLocalID: project.localID,
                    payload: Self.encode(FilterDeletePayload(remoteID: id)),
                    createdAt: Date(),
                    retryCount: 0,
                    lastError: nil,
                    status: .pending,
                    needsConflictResolution: false,
                )
                try item.insert(db)
            }
        }
        await drainIfOnline()
    }

    private func cachedFilter(id: Int) async throws -> CachedFilter? {
        try await localStore.read { db in
            guard let (project, savedFilter) = try Self.rows(for: id, accountID: self.accountID, db: db) else {
                return nil
            }
            return CachedFilter(
                detail: Self.detail(project: project, savedFilter: savedFilter),
                lastPulledAt: savedFilter.lastPulledAt,
            )
        }
    }

    private func storeQuery(_ query: String, for id: Int) async throws -> SavedFilterDetail {
        try await localStore.write { db in
            guard let (project, savedFilter) = try Self.rows(for: id, accountID: self.accountID, db: db) else {
                throw VikunjaError.notFound
            }
            var updatedCache = savedFilter
            try updatedCache.storeQuery(query, pulledAt: Date(), db: db)
            return Self.detail(project: project, savedFilter: updatedCache)
        }
    }

    private func refreshQuery(id: Int) async throws {
        let remote = try await networkRepository.fetchFilter(id: id)
        _ = try await storeQuery(remote.query, for: id)
    }

    private func drainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainFilterMutations()
    }

    private struct CachedFilter {
        let detail: SavedFilterDetail
        let lastPulledAt: Date?
    }

    private static func rows(for remoteID: Int, accountID: UUID, db: Database) throws -> (ProjectRecord, SavedFilterRecord)? {
        guard let savedFilter = try SavedFilterRecord
            .filter(Column("accountID") == accountID && Column("remoteID") == remoteID)
            .fetchOne(db),
            let project = try ProjectRecord.fetchOne(db, key: savedFilter.projectLocalID),
            project.accountID == accountID,
            project.remoteID == -savedFilter.remoteID - 1
        else { return nil }
        return (project, savedFilter)
    }

    private static func detail(project: ProjectRecord, savedFilter: SavedFilterRecord) -> SavedFilterDetail {
        SavedFilterDetail(
            id: savedFilter.remoteID,
            title: project.title,
            description: project.description ?? "",
            isFavorite: project.isFavorite,
            query: savedFilter.query,
        )
    }

    private static func enqueueRename(
        _ payload: FilterRenamePayload,
        targetLocalID: UUID,
        accountID: UUID,
        db: Database,
    ) throws {
        let encoded = try encode(payload)
        if var existing = try MutationQueueRecord.fetchAll(db).first(where: {
            $0.accountID == accountID && $0.entityType == .filter && $0.targetLocalID == targetLocalID
                && $0.operation == .update && ($0.status == .pending || $0.status == .failed)
        }) {
            existing.payload = encoded
            existing.status = .pending
            existing.lastError = nil
            existing.retryCount = 0
            existing.needsConflictResolution = false
            try existing.update(db)
        } else {
            var item = MutationQueueRecord(
                id: nil,
                accountID: accountID,
                entityType: .filter,
                operation: .update,
                targetLocalID: targetLocalID,
                payload: encoded,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
