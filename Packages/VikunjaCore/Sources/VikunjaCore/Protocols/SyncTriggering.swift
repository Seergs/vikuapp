import Foundation

/// An explicit synchronization command, bound to one account at composition.
/// Repository queries never invoke this command.
public protocol SyncTriggering: Sendable {
    func hasInitialSnapshot() async throws -> Bool
    /// Download an initial snapshot when this account has not been synced.
    func prepare() async throws
    func refresh(scope: SyncScope) async throws
}

public enum SyncScope: Hashable, Sendable {
    /// Upload queued changes before downloading the board.
    case kanban(projectID: EntityID)
    case account
    /// Also refresh the task's comment thread; attachments remain online-only.
    case task(EntityID)
    /// Demand-load a comment thread without refreshing the entire account.
    case comments(EntityID)

    public var includesAccount: Bool {
        switch self {
        case .account, .task, .kanban: true
        case .comments: false
        }
    }

    public var kanbanProjectID: EntityID? {
        if case let .kanban(id) = self {
            return id
        }
        return nil
    }

    public var commentTaskID: EntityID? {
        switch self {
        case .account, .kanban: nil
        case let .task(id), let .comments(id): id
        }
    }
}

/// Schedules durable local writes for upload without waiting for the network.
public protocol SyncRequesting: Sendable {
    func requestSync() async
}

/// Account-scoped database invalidations. Consumers re-read their local queries.
/// Includes an initial value, then changes; cancellation releases observation.
public protocol LocalDataObserving: Sendable {
    func localChanges() async -> AsyncThrowingStream<Void, Error>
}
