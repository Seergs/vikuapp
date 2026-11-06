import Foundation

/// One explicit value applied identically to every task in a bulk request.
/// It never toggles a task relative to its previous state or replaces
/// unrelated task fields.
public enum TaskBulkChange: Sendable, Hashable {
    case completion(isDone: Bool)
    /// Sets the same due date on every task, e.g. moving overdue tasks to
    /// the end of today or tomorrow.
    case dueDate(Date)
}

/// Applies one `TaskBulkChange` to a group of tasks.
///
/// The transport implementation accepts server IDs only and returns the server's
/// updated tasks, matched by ID rather than by array position. An empty selection
/// is a no-op; duplicate IDs represent one task. A rejected batch throws rather
/// than reporting individual successes. Persistence and queued synchronization
/// are the responsibility of local adapters rather than the transport.
public protocol TaskBulkUpdateRepositoryProtocol: Sendable {
    func apply(_ change: TaskBulkChange, toTaskIDs taskIDs: [EntityID]) async throws -> [VikunjaTask]
}

public extension TaskBulkUpdateRepositoryProtocol {
    func setCompletion(taskIDs: [EntityID], isDone: Bool) async throws -> [VikunjaTask] {
        try await apply(.completion(isDone: isDone), toTaskIDs: taskIDs)
    }

    func setDueDate(taskIDs: [EntityID], dueDate: Date) async throws -> [VikunjaTask] {
        try await apply(.dueDate(dueDate), toTaskIDs: taskIDs)
    }
}
