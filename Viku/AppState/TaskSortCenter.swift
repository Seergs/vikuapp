import Foundation
import Observation
import VikunjaCore

/// Owns the user's task sort preference: which field to sort on and in which
/// direction. Reads from `UserDefaults` on launch (a plain UI preference, not a
/// credential, so `UserDefaults` — not the Keychain — is the right home) and
/// persists every change. One instance lives for the whole app — created once
/// by the composition root — and is handed to ViewModels as `TaskSortStore` so
/// they never know how it's persisted.
@Observable
@MainActor
final class TaskSortCenter: TaskSortStore {
    private static let fieldKey = "taskSort.field"
    private static let directionKey = "taskSort.direction"

    private(set) var taskSort: TaskSort

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fieldRaw = defaults.string(forKey: Self.fieldKey) ?? TaskSort.Field.dueDate.rawValue
        let directionRaw = defaults.string(forKey: Self.directionKey) ?? TaskSort.Direction.ascending.rawValue
        let field = TaskSort.Field(rawValue: fieldRaw) ?? .dueDate
        let direction = TaskSort.Direction(rawValue: directionRaw) ?? .ascending
        self.taskSort = TaskSort(field: field, direction: direction)
    }

    func setTaskSort(_ sort: TaskSort) {
        taskSort = sort
        defaults.set(sort.field.rawValue, forKey: Self.fieldKey)
        defaults.set(sort.direction.rawValue, forKey: Self.directionKey)
    }
}
