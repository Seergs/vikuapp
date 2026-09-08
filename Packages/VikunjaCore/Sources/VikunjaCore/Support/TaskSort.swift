import Foundation

/// A user-chosen ordering for a task list: which field to sort on and in
/// which direction. The comparison rule lives here rather than in a view so
/// it stays pure, testable without networking, and reusable across screens —
/// same reasoning as `TodayDigest`.
public struct TaskSort: Sendable, Hashable, Codable {
    public enum Field: String, Sendable, CaseIterable, Hashable, Codable {
        case dueDate
        case priority
        case title
    }

    public enum Direction: String, Sendable, CaseIterable, Hashable, Codable {
        case ascending
        case descending
    }

    public var field: Field
    public var direction: Direction

    public init(field: Field, direction: Direction) {
        self.field = field
        self.direction = direction
    }

    /// Earliest due date first — the order every task list used before
    /// sorting became selectable.
    public static let `default` = TaskSort(field: .dueDate, direction: .ascending)

    /// `tasks` reordered by this sort. A task with no due date always sorts
    /// after one that has a due date, regardless of direction — an unset date
    /// is "no information", not a value at either extreme. Ties on the chosen
    /// field break by ascending task id, so the result is stable.
    public func sorted(_ tasks: [VikunjaTask]) -> [VikunjaTask] {
        tasks.sorted { lhs, rhs in
            switch primaryComparison(lhs, rhs) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
    }

    private func primaryComparison(_ lhs: VikunjaTask, _ rhs: VikunjaTask) -> ComparisonResult {
        switch field {
        case .dueDate:
            dueDateComparison(lhs.dueDate, rhs.dueDate)
        case .priority:
            directed(compare(lhs.priority.rawValue, rhs.priority.rawValue))
        case .title:
            directed(lhs.title.localizedCaseInsensitiveCompare(rhs.title))
        }
    }

    /// Present dates compare normally (and honor `direction`); a missing date
    /// is pinned last either way.
    private func dueDateComparison(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): directed(compare(lhs, rhs))
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        }
    }

    private func directed(_ result: ComparisonResult) -> ComparisonResult {
        guard direction == .descending else { return result }
        return switch result {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }
}
