import Foundation
import GRDB

/// Process-wide execution permission for the app's managed databases. iOS lifecycle
/// callbacks update this synchronously, before returning background time to the OS.
/// Standalone stores (including widget readers and most tests) do not opt in.
public final class DatabaseExecutionLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var foreground = true
    private var windows: Set<UUID> = []
    private var workers: [UUID: Task<Void, Error>] = [:]
    private var generation = 0
    private var suspended = false
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    public init() {}

    public var isSuspended: Bool {
        lock.withLock { suspended }
    }

    var suspensionGeneration: Int {
        lock.withLock { generation }
    }

    public func setForeground(_ value: Bool) {
        update { foreground = value }
    }

    @discardableResult
    public func beginBackgroundExecution() -> UUID {
        let id = UUID()
        update { windows.insert(id) }
        return id
    }

    public func endBackgroundExecution(_ id: UUID) {
        update { windows.remove(id) }
    }

    private func update(_ change: () -> Void) {
        // Serialize notifications with state changes, including rapid foreground /
        // expiration races. GRDB's notification handlers only touch its own locks.
        lock.lock()
        change()
        let shouldSuspend = !foreground && windows.isEmpty
        guard suspended != shouldSuspend else { lock.unlock(); return }
        suspended = shouldSuspend
        if shouldSuspend {
            generation += 1
            NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
        } else {
            NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
        }
        let cancelled = shouldSuspend ? Array(workers.values) : []
        let resumed = shouldSuspend ? [] : Array(waiters.values)
        if !shouldSuspend {
            waiters.removeAll()
        }
        lock.unlock()
        for worker in cancelled {
            worker.cancel()
        }
        for waiter in resumed {
            waiter.resume()
        }
    }

    func waitForWorkers() async {
        while !Task.isCancelled {
            let tasks = lock.withLock { Array(workers.values) }
            guard !tasks.isEmpty else { return }
            for task in tasks {
                _ = await task.result
            }
        }
    }

    func track(_ task: Task<Void, Error>, id: UUID) {
        let shouldCancel = lock.withLock {
            workers[id] = task
            return suspended
        }
        if shouldCancel {
            task.cancel()
        }
    }

    func untrack(_ id: UUID) {
        _ = lock.withLock { workers.removeValue(forKey: id) }
    }

    func checkAccess() throws {
        try Task.checkCancellation()
        if isSuspended {
            throw CancellationError()
        }
    }

    func waitUntilResumed() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if !suspended {
                        continuation.resume()
                    } else {
                        waiters[id] = continuation
                    }
                }
            }
        } onCancel: {
            let waiter = self.lock.withLock { self.waiters.removeValue(forKey: id) }
            waiter?.resume(throwing: CancellationError())
        }
    }
}

/// A cancelled request can surface as URLError rather than CancellationError.
/// Database interruption is normalized at LocalStore's boundary.
func checkSyncInterruption(_ error: any Error) throws {
    try Task.checkCancellation()
    if error is CancellationError || (error as? URLError)?.code == .cancelled {
        throw CancellationError()
    }
}
