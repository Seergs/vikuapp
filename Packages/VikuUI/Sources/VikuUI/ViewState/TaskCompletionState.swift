import VikunjaCore

/// Keeps local snapshots from undoing completion edits that have not reached
/// storage yet. Other task fields and snapshot membership remain authoritative.
public struct TaskCompletionState {
    private var pending: [EntityID: VikunjaTask] = [:]

    public init() {}

    /// Ignore repeated taps while this task's local write is pending. Writes
    /// for different tasks remain independent and can proceed concurrently.
    public mutating func begin(_ task: VikunjaTask) -> VikunjaTask? {
        guard pending[task.id] == nil else { return nil }
        var flipped = task
        flipped.isDone.toggle()
        pending[task.id] = flipped
        return flipped
    }

    public func applying(to snapshot: [VikunjaTask]) -> [VikunjaTask] {
        snapshot.map { task in
            guard let edit = pending[task.id] else { return task }
            var updated = task
            updated.isDone = edit.isDone
            return updated
        }
    }

    /// Resolve by identity, preserving unrelated fields refreshed during the
    /// write. A task removed from the snapshot must never be resurrected.
    public mutating func resolve(_ result: VikunjaTask, in tasks: inout [VikunjaTask]) {
        guard let expected = pending.removeValue(forKey: result.id),
              let index = tasks.firstIndex(where: { $0.id == result.id }) else { return }
        if tasks[index] == expected {
            tasks[index] = result
        } else {
            tasks[index].isDone = result.isDone
        }
    }
}
