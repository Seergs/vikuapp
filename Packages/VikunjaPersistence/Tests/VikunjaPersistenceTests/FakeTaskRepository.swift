import Foundation
import VikunjaCore

final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var fetchError: Error?
    /// Lets a test fail one project's fetch while another project's still
    /// succeeds, mirroring one endpoint erroring mid-`pullTasks()`.
    var fetchErrorsByProjectID: [Int: Error] = [:]
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    var searchError: Error?
    private(set) var createdTasks: [VikunjaTask] = []
    private(set) var updatedTasks: [VikunjaTask] = []
    private(set) var deletedIDs: [Int] = []
    private(set) var fetchTasksCallCount = 0
    private var nextRemoteID = 100

    func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        fetchTasksCallCount += 1
        if let fetchError {
            throw fetchError
        }
        if let remoteID = projectID.remoteValue, let error = fetchErrorsByProjectID[remoteID] {
            throw error
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: EntityID) async throws -> VikunjaTask {
        if let fetchError {
            throw fetchError
        }
        guard let task = tasks.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return task
    }

    /// Mirrors `FakeProjectRepository.create` - also adds the created task
    /// to `tasks`, like a real server would list it back on the very next
    /// `fetchTasks()` call. Stamps `updated` like a real create response
    /// would, so conflict-detection tests have something to compare against.
    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let createError {
            throw createError
        }
        createdTasks.append(task)
        let remoteID = nextRemoteID
        nextRemoteID += 1
        let created = VikunjaTask(
            id: .remote(remoteID),
            title: task.title,
            description: task.description,
            isDone: task.isDone,
            dueDate: task.dueDate,
            priority: task.priority,
            projectID: task.projectID,
            reminders: task.reminders,
            updated: Date(),
        )
        tasks.append(created)
        return created
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let updateError {
            throw updateError
        }
        updatedTasks.append(task)
        var updated = task
        updated.updated = Date()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = updated
        }
        return updated
    }

    func delete(id: EntityID) async throws {
        if let deleteError {
            throw deleteError
        }
        if let remoteID = id.remoteValue {
            deletedIDs.append(remoteID)
        }
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        if let searchError {
            throw searchError
        }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
