#if DEBUG
import Foundation
import VikunjaCore

/// One fake server instance is shared by every repository consumer for this launch.
actor UITestTaskRepository: TaskRepositoryProtocol, TaskBulkUpdateRepositoryProtocol {
    private var tasks: [VikunjaTask]
    private var nextID = 100

    init() {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        // Relative calendar days keep the fixture in the same digest buckets on any date.
        self.tasks = [
            VikunjaTask(id: 1, title: "UI Test: Plan today", dueDate: calendar.startOfDay(for: noon), projectID: 1),
            VikunjaTask(
                id: 2, title: "UI Test: Review overdue", dueDate: calendar.date(byAdding: .day, value: -1, to: noon),
                projectID: 1,
            ),
        ]
    }

    func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: EntityID) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return task
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        tasks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        let created = VikunjaTask(
            id: .remote(nextID), title: task.title, description: task.description, isDone: task.isDone,
            dueDate: task.dueDate, priority: task.priority, projectID: task.projectID, labels: task.labels,
            subtasks: task.subtasks, dependsOn: task.dependsOn, blocks: task.blocks,
            otherRelations: task.otherRelations, reminders: task.reminders, updated: Date(),
        )
        nextID += 1
        tasks.append(created)
        return created
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { throw VikunjaError.notFound }
        var updated = task
        updated.updated = Date()
        tasks[index] = updated
        return updated
    }

    func delete(id: EntityID) async throws {
        tasks.removeAll { $0.id == id }
    }

    func apply(_ change: TaskBulkChange, toTaskIDs taskIDs: [EntityID]) async throws -> [VikunjaTask] {
        let ids = Set(taskIDs)
        guard ids.isSubset(of: Set(tasks.map(\.id))) else { throw VikunjaError.notFound }
        return tasks.indices.filter { ids.contains(tasks[$0].id) }.map { index in
            switch change {
            case let .completion(isDone): tasks[index].isDone = isDone
            case let .dueDate(date): tasks[index].dueDate = date
            }
            tasks[index].updated = Date()
            return tasks[index]
        }
    }
}
#endif
