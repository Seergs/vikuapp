import Foundation

/// A task's destination within its current bucket, independently of completion.
public enum KanbanTaskPlacement: String, Codable, Sendable, CaseIterable {
    case top
    case bottom

    /// Positions are scoped to a view. Callers pass only this bucket's peers.
    /// Negative cached positions are valid locally; the server may renormalize them.
    public func position(among peers: [Double]) throws -> Double {
        guard peers.allSatisfy(\.isFinite) else { throw VikunjaError.decoding("Non-finite task position") }
        guard let minimum = peers.min(), let maximum = peers.max() else { return 65536 }
        let result: Double = switch self {
        case .top: minimum > 0 ? minimum / 2 : minimum - 65536
        case .bottom: maximum + max(65536, abs(maximum) * Double.ulpOfOne * 4)
        }
        guard result.isFinite, self == .top ? result < minimum : result > maximum else {
            throw VikunjaError.decoding("Task position range exhausted")
        }
        return result == 0 ? -65536 : result
    }
}

/// The server may renormalize the requested value; use its returned position.
public struct TaskViewPosition: Sendable, Equatable {
    public let taskID: Int
    public let viewID: Int
    public let position: Double

    public init(taskID: Int, viewID: Int, position: Double) {
        self.taskID = taskID
        self.viewID = viewID
        self.position = position
    }
}

public extension KanbanTaskPlacement {
    /// Resolves an edge from a complete server snapshot. Nil is an already-satisfied command.
    func position(in download: KanbanDownload, taskID: Int, bucketID: Int) throws -> Double? {
        guard let bucket = download.buckets.first(where: { $0.id == bucketID }),
              bucket.tasks.contains(where: { $0.id == .remote(taskID) }) else { throw VikunjaError.notFound }
        let edge = self == .top ? bucket.tasks.first : bucket.tasks.last
        guard edge?.id != .remote(taskID) else { return nil }
        let peers = try bucket.tasks.filter { $0.id != .remote(taskID) }.map { task -> Double in
            guard let id = task.id.remoteValue, let value = download.taskPositions[id], value.isFinite, value > 0 else {
                throw VikunjaError.decoding("Missing per-view task position")
            }
            return value
        }
        return try position(among: peers)
    }
}
