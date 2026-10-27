import VikunjaCore

public final class VikunjaTaskRepository: TaskRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        // A project with no remote id yet (offline-created) has no tasks on
        // the server to fetch either.
        guard let remoteID = projectID.remoteValue else { return [] }
        let dtos: [TaskDTO] = try await client.send(VikunjaEndpoints.tasks(projectID: remoteID))
        return dtos.map(TaskMapper.toDomain)
    }

    public func fetchTask(id: EntityID) async throws -> VikunjaTask {
        guard let remoteID = id.remoteValue else {
            throw VikunjaError.notFound
        }
        let dto: TaskDTO = try await client.send(VikunjaEndpoints.task(id: remoteID))
        return TaskMapper.toDomain(dto)
    }

    public func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        // The task's project must be synced before this repository — the
        // raw network layer, with no queue of its own — can create a task
        // under it at all.
        guard let projectID = task.projectID.remoteValue else {
            throw VikunjaError.notFound
        }
        let endpoint = try VikunjaEndpoints.createTask(projectID: projectID, dto: TaskMapper.toDTO(task))
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    /// Vikunja's update endpoint replaces the whole task with the request
    /// body — any field the body omits gets reset to zero/null server-side
    /// rather than left alone (github.com/go-vikunja/vikunja/issues/1459).
    /// Fetching the current state first and merging our change on top of it
    /// (`TaskMapper.merge`) is the only way to update just one field without
    /// silently wiping the rest — including fields `VikunjaTask` doesn't
    /// even represent, like `percent_done`.
    public func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        guard let taskID = task.id.remoteValue else {
            throw VikunjaError.notFound
        }
        let current: TaskDTO = try await client.send(VikunjaEndpoints.task(id: taskID))
        let endpoint = try VikunjaEndpoints.updateTask(id: taskID, dto: TaskMapper.merge(task, onto: current))
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    public func delete(id: EntityID) async throws {
        guard let remoteID = id.remoteValue else {
            throw VikunjaError.notFound
        }
        try await client.send(VikunjaEndpoints.deleteTask(id: remoteID))
    }

    public func searchTasks(query: String) async throws -> [VikunjaTask] {
        let dtos: [TaskDTO] = try await client.send(VikunjaEndpoints.searchTasks(query: query))
        return dtos.map(TaskMapper.toDomain)
    }
}
