/// Sets one explicit completion state for a group of tasks. It never toggles
/// each task relative to its previous state or replaces unrelated task fields.
///
/// The transport implementation accepts server IDs only and returns the server's
/// updated tasks, matched by ID rather than by array position. An empty selection
/// is a no-op; duplicate IDs represent one task. A rejected batch throws rather
/// than reporting individual successes. Persistence and queued synchronization
/// are the responsibility of local adapters rather than the transport.
public protocol TaskBulkCompletionRepositoryProtocol: Sendable {
    func setCompletion(taskIDs: [EntityID], isDone: Bool) async throws -> [VikunjaTask]
}
