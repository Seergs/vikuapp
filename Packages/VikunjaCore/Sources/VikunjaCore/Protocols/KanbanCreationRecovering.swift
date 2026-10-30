/// Recovery is available only after the server has definitively rejected creation.
/// Unknown outcomes must be checked on the server before submitting another POST.
public protocol KanbanCreationRecovering: Sendable {
    /// Current cached destinations, excluding the task being recovered from occupancy.
    func recoveryBuckets(operationID: Int64) async throws -> [KanbanCreationBucket]
    /// `nil` retries the current destination. A different bucket changes the same local task.
    func retryCreation(operationID: Int64, bucketID: Int?) async throws
    func deleteRejectedCreation(operationID: Int64) async throws
}
