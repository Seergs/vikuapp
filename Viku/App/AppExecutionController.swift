import BackgroundTasks
import UIKit
import VikunjaPersistence

/// Owns UIKit assertions separately from database permission. Each callback has
/// its own lease, so finishing widgets cannot revoke a scheduled sync's window.
@MainActor
final class AppExecutionController {
    private let lifecycle: DatabaseExecutionLifecycle
    private var assertions: [UUID: UIBackgroundTaskIdentifier] = [:]
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var completions: [UUID: () -> Void] = [:]

    init(lifecycle: DatabaseExecutionLifecycle) {
        self.lifecycle = lifecycle
    }

    func enterForeground() {
        lifecycle.setForeground(true)
    }

    func enterBackground(operation: @escaping @MainActor () async -> Void) {
        startBackgroundOperation(operation: operation)
        lifecycle.setForeground(false)
    }

    private func startBackgroundOperation(
        operation: @escaping @MainActor () async -> Void,
        completion: @escaping () -> Void = {},
    ) {
        let id = lifecycle.beginBackgroundExecution()
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "FinishDatabaseWork") { [weak self] in
            // UIKit invokes this expiration handler on the main thread. Suspend
            // synchronously before returning execution time, not in a queued Task.
            MainActor.assumeIsolated { self?.finish(id) }
        }
        if assertion != .invalid {
            completions[id] = completion
            assertions[id] = assertion
            operations[id] = Task { [weak self] in
                await operation()
                self?.finish(id)
            }
        } else {
            lifecycle.endBackgroundExecution(id)
            completion()
        }
    }

    private func finish(_ id: UUID) {
        operations.removeValue(forKey: id)?.cancel()
        lifecycle.endBackgroundExecution(id)
        if let assertion = assertions.removeValue(forKey: id) {
            UIApplication.shared.endBackgroundTask(assertion)
        }
        completions.removeValue(forKey: id)?()
    }

    func runScheduledSync(_ task: BGTask, coordinator: SyncCoordinator) {
        let id = lifecycle.beginBackgroundExecution()
        let lifecycle = lifecycle
        let operation = Task {
            await coordinator.syncAllAccounts()
            // Finish the DB window before telling the scheduler we're done.
            lifecycle.endBackgroundExecution(id)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            operation.cancel()
            lifecycle.endBackgroundExecution(id)
        }
    }

    /// Give notification actions an expiring assertion as well, so a stalled
    /// request cannot hold the callback's database permission indefinitely.
    func runNotificationAction(
        operation: @escaping @MainActor () async -> Void,
        completion: @escaping () -> Void,
    ) {
        startBackgroundOperation(operation: operation, completion: completion)
    }
}
