import Foundation
import VikunjaCore

/// Retains departing rows independently of the live queue. A burst of queue
/// updates never skips a visible row or delays the actual synchronization.
struct PendingSyncPresentation {
    static let departureInterval: Duration = .milliseconds(600)

    private(set) var operations: [PendingSyncOperation] = []
    private var departures: [Int64: ContinuousClock.Instant] = [:]
    private var lastDeparture: ContinuousClock.Instant?

    var nextUpdate: ContinuousClock.Instant? {
        guard let first = operations.first(where: { departures[$0.id] != nil }),
              let deadline = departures[first.id]
        else { return nil }
        return max(deadline, lastDeparture?.advanced(by: Self.departureInterval) ?? deadline)
    }

    mutating func receive(
        _ snapshot: [PendingSyncOperation],
        at now: ContinuousClock.Instant = .now,
        reset: Bool = false,
    ) {
        if reset {
            operations = snapshot
            departures = [:]
            lastDeparture = nil
            return
        }

        let current = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        let visibleIDs = Set(operations.map(\.id))
        operations = operations.map { current[$0.id] ?? $0 }
        operations.append(contentsOf: snapshot.filter { !visibleIDs.contains($0.id) })

        for operation in operations {
            if current[operation.id] != nil {
                departures[operation.id] = nil
            } else if departures[operation.id] == nil {
                departures[operation.id] = now.advanced(by: Self.departureInterval)
            }
        }
    }

    mutating func advance(at now: ContinuousClock.Instant = .now) {
        guard let deadline = nextUpdate, now >= deadline,
              let index = operations.firstIndex(where: { departures[$0.id] != nil })
        else { return }
        departures[operations[index].id] = nil
        operations.remove(at: index)
        // Use actual presentation time: after a suspension, do not catch up
        // with a burst of removals that would defeat the visual cadence.
        lastDeparture = now
    }
}
