import VikunjaCore

public final class VikunjaTaskRepository: TaskRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        let dtos: [TaskDTO] = try await client.send(VikunjaEndpoints.tasks(projectID: projectID))
        return dtos.map(TaskMapper.toDomain)
    }

    public func fetchTask(id: Int) async throws -> VikunjaTask {
        let dto: TaskDTO = try await client.send(VikunjaEndpoints.task(id: id))
        return TaskMapper.toDomain(dto)
    }

    public func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        let endpoint = try VikunjaEndpoints.createTask(projectID: task.projectID, dto: TaskMapper.toDTO(task))
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
        let current: TaskDTO = try await client.send(VikunjaEndpoints.task(id: task.id))
        let endpoint = try VikunjaEndpoints.updateTask(id: task.id, dto: TaskMapper.merge(task, onto: current))
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    public func delete(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteTask(id: id))
    }

    public func searchTasks(query: String) async throws -> [VikunjaTask] {
        let dtos: [TaskDTO] = try await client.send(VikunjaEndpoints.searchTasks(query: query))
        return dtos.map(TaskMapper.toDomain)
    }
}
