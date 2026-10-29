import Foundation
import Network

/// The two things a future sync engine needs from the network: "we just
/// came back online" (a stream to drain a mutation queue on), and a plain
/// current-status read for deciding whether to attempt a sync immediately
/// after a local change. Multiple subscribers can each hold their own
/// `reachabilityRegained()` stream. Nothing consumes this yet, so it's
/// unused/dead code until the sync engine that needs it exists.
public protocol ReachabilityMonitoring: Sendable {
    /// Whether the network is reachable right now.
    var isReachable: Bool { get async }

    /// Yields once per transition from unreachable to reachable. Never
    /// fires for the initial status report on startup (there's no prior
    /// "unreachable" to transition from), and never more than once per
    /// continuous reachable streak.
    func reachabilityRegained() async -> AsyncStream<Void>

    /// Emits the current reachability and every subsequent path change.
    func reachabilityUpdates() async -> AsyncStream<Bool>
}

public extension ReachabilityMonitoring {
    func reachabilityUpdates() async -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                await continuation.yield(isReachable)
                let regained = await reachabilityRegained()
                for await _ in regained {
                    continuation.yield(true)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// `NWPathMonitor`-backed `ReachabilityMonitoring`. `PathMonitor` is a thin
/// seam around it (see below) so the offline/online transition logic here
/// can be tested without a real network interface.
public actor NWPathReachabilityMonitor: ReachabilityMonitoring {
    private let pathMonitor: PathMonitor
    /// `nil` until the first path update arrives, so that first report (in
    /// either direction) establishes a baseline instead of being read as a
    /// transition from a default "offline" guess.
    private var satisfied: Bool?
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init(queue: DispatchQueue = DispatchQueue(label: "app.viku.reachability")) {
        self.init(pathMonitor: SystemPathMonitor(), queue: queue)
    }

    init(pathMonitor: PathMonitor, queue: DispatchQueue) {
        self.pathMonitor = pathMonitor
        pathMonitor.setUpdateHandler { [weak self] isSatisfied in
            Task { await self?.handle(isSatisfied: isSatisfied) }
        }
        pathMonitor.start(queue: queue)
    }

    deinit {
        pathMonitor.cancel()
    }

    public var isReachable: Bool {
        satisfied ?? false
    }

    public func reachabilityRegained() async -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func reachabilityUpdates() async -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            statusContinuations[id] = continuation
            if let satisfied {
                continuation.yield(satisfied)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStatusContinuation(id) }
            }
        }
    }

    private func handle(isSatisfied: Bool) {
        let wasSatisfied = satisfied
        satisfied = isSatisfied
        for continuation in statusContinuations.values {
            continuation.yield(isSatisfied)
        }
        guard isSatisfied, wasSatisfied == false else { return }
        for continuation in continuations.values {
            continuation.yield()
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }
}

/// Mirrors just the two things `NWPathReachabilityMonitor` needs from
/// `NWPathMonitor`, collapsing `NWPath` to the one bit that matters
/// (`status == .satisfied`) so a fake can report transitions without
/// constructing a real `NWPath`.
protocol PathMonitor: Sendable {
    func setUpdateHandler(_ handler: @escaping @Sendable (Bool) -> Void)
    func start(queue: DispatchQueue)
    func cancel()
}

/// The real `NWPathMonitor` wrapper `NWPathReachabilityMonitor` uses outside
/// tests. `NWPathMonitor` itself documents `start`/`cancel`/handler
/// assignment as safe to call from any thread, which is what this type
/// relies on to be `Sendable`.
final class SystemPathMonitor: PathMonitor, @unchecked Sendable {
    private let monitor = NWPathMonitor()

    func setUpdateHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in handler(path.status == .satisfied) }
    }

    func start(queue: DispatchQueue) {
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
