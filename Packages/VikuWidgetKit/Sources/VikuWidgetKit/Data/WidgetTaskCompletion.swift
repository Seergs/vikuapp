import Foundation
import VikunjaCore

/// Explicit target state makes replaying a tap from an old timeline idempotent.
/// The local-acceptance callback runs before server work.
public struct WidgetTaskCompletion: Sendable {
    private let repository: any TaskBulkUpdateRepositoryProtocol
    private let synchronize: @Sendable () async throws -> Void
    private let reload: @Sendable () async -> Void

    public init(
        repository: any TaskBulkUpdateRepositoryProtocol,
        synchronize: @escaping @Sendable () async throws -> Void,
        reload: @escaping @Sendable () async -> Void,
    ) {
        self.repository = repository
        self.synchronize = synchronize
        self.reload = reload
    }

    public func setCompletion(taskID: Int, isDone: Bool) async throws {
        _ = try await repository.setCompletion(taskIDs: [.remote(taskID)], isDone: isDone)
        await reload()
        // A failed upload must not report the accepted local change as failed.
        // Pending Sync retains failures and conflicts for recovery in the app.
        try? await synchronize()
    }
}
