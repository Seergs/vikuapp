import Foundation
import GRDB
import VikunjaCore

public struct OfflineKanbanBoardRepository: KanbanBoardRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID

    public init(localStore: LocalStore, accountID: UUID) {
        self.localStore = localStore
        self.accountID = accountID
    }

    public func fetchBoard(projectID: EntityID, viewID: Int) async throws -> KanbanBoardSnapshot {
        try await localStore.read { db in
            let project = try ProjectRecord.filter(Column("accountID") == accountID).fetchAll(db).first {
                projectID == .local($0.localID) || $0.remoteID.map(EntityID.remote) == projectID
            }
            guard let project,
                  let view = try KanbanViewRecord.filter(Column("accountID") == accountID)
                  .filter(Column("projectLocalID") == project.localID)
                  .filter(Column("remoteID") == viewID).fetchOne(db),
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
                supportsOfflineWrites: view.mode == "manual"
                    && view.filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                lastPulledAt: pulledAt,
            ))
        }
    }
}
