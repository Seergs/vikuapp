import Foundation

/// A widget is given a short execution opportunity, not a persistent worker.
/// Cancelling the deadline must cancel the actual sync worker as well.
enum WidgetSynchronization {
    static func run(
        budget: Duration = .seconds(8),
        operation: @escaping @Sendable () async throws -> Void,
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: budget)
                throw CancellationError()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
