import Foundation
import Testing
@testable import VikunjaCore

struct TaskSortTests {
    private static let calendar = Calendar.current
    private static let now = calendar.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(),
    ) ?? Date()
    private static let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    private static let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now

    private func task(
        _ id: Int,
        title: String = "Task",
        due: Date? = nil,
        priority: VikunjaTask.Priority = .unset,
    ) -> VikunjaTask {
        VikunjaTask(id: id, title: title, dueDate: due, priority: priority, projectID: 1)
    }

    @Test
    func `sorts by due date ascending with missing dates last`() {
        let sort = TaskSort(field: .dueDate, direction: .ascending)
        let tasks = [
            task(1, due: Self.tomorrow),
            task(2),
            task(3, due: Self.yesterday),
        ]

        #expect(sort.sorted(tasks).map(\.id) == [3, 1, 2])
    }

    @Test
    func `sorts by due date descending but still keeps missing dates last`() {
        let sort = TaskSort(field: .dueDate, direction: .descending)
        let tasks = [
            task(1, due: Self.yesterday),
            task(2),
            task(3, due: Self.tomorrow),
        ]

        #expect(sort.sorted(tasks).map(\.id) == [3, 1, 2])
    }

    @Test
    func `sorts by priority descending puts urgent first`() {
        let sort = TaskSort(field: .priority, direction: .descending)
        let tasks = [
            task(1, priority: .low),
            task(2, priority: .urgent),
            task(3, priority: .medium),
        ]

        #expect(sort.sorted(tasks).map(\.id) == [2, 3, 1])
    }

    @Test
    func `sorts by priority ascending puts unset first`() {
        let sort = TaskSort(field: .priority, direction: .ascending)
        let tasks = [
            task(1, priority: .high),
            task(2, priority: .unset),
            task(3, priority: .low),
        ]

        #expect(sort.sorted(tasks).map(\.id) == [2, 3, 1])
    }

    @Test
    func `sorts by title case-insensitively`() {
        let ascending = TaskSort(field: .title, direction: .ascending)
        let tasks = [
            task(1, title: "banana"),
            task(2, title: "Apple"),
            task(3, title: "cherry"),
        ]

        #expect(ascending.sorted(tasks).map(\.id) == [2, 1, 3])
        #expect(TaskSort(field: .title, direction: .descending).sorted(tasks).map(\.id) == [3, 1, 2])
    }

    @Test
    func `breaks ties by ascending id regardless of direction`() {
        let tasks = [task(3, priority: .high), task(1, priority: .high), task(2, priority: .high)]

        #expect(TaskSort(field: .priority, direction: .ascending).sorted(tasks).map(\.id) == [1, 2, 3])
        #expect(TaskSort(field: .priority, direction: .descending).sorted(tasks).map(\.id) == [1, 2, 3])
    }

    @Test
    func `default sort is due date ascending`() {
        #expect(TaskSort.default == TaskSort(field: .dueDate, direction: .ascending))
    }
}
