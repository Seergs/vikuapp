import Foundation
import Observation

/// Owns presentation timing independently of SwiftUI rendering or task identity.
/// Callers publish loading transitions immediately; the underlying read never waits.
@MainActor
@Observable
final class PendingSyncLoadingIndicator {
    private(set) var isVisible = false
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var shownAt: ContinuousClock.Instant?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    private let now: @MainActor () -> ContinuousClock.Instant
    private let sleepUntil: @MainActor (ContinuousClock.Instant) async throws -> Void

    init(
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
        sleepUntil: @escaping @MainActor (ContinuousClock.Instant) async throws -> Void = {
            try await ContinuousClock().sleep(until: $0)
        },
    ) {
        self.now = now
        self.sleepUntil = sleepUntil
    }

    deinit { transition?.cancel() }

    @discardableResult
    func setLoading(_ loading: Bool) -> Task<Void, Never>? {
        guard loading != isLoading else { return transition }
        isLoading = loading
        generation += 1
        transition?.cancel()
        transition = nil

        if loading, !isVisible {
            return schedule(visible: true, at: now().advanced(by: .seconds(1)))
        }
        if !loading, let shownAt {
            return schedule(visible: false, at: shownAt.advanced(by: .seconds(1)))
        }
        return nil
    }

    /// Leaving the screen cancels its presentation, not the account's sync work.
    func reset() {
        generation += 1
        transition?.cancel()
        transition = nil
        isLoading = false
        isVisible = false
        shownAt = nil
    }

    private func schedule(visible: Bool, at deadline: ContinuousClock.Instant) -> Task<Void, Never> {
        let generation = generation
        let sleep = sleepUntil
        let task = Task { [weak self] in
            do {
                try await sleep(deadline)
                guard !Task.isCancelled, let self,
                      self.generation == generation, isLoading == visible else { return }
                isVisible = visible
                shownAt = visible ? now() : nil
            } catch {
                // A later transition or leaving the screen cancels this timer.
            }
        }
        transition = task
        return task
    }
}
