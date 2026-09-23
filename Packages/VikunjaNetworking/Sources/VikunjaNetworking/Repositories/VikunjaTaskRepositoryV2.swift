import VikunjaCore

/// v2 implementation of `TaskRepositoryProtocol`. Reuses v1's `TaskDTO` /
/// `TaskMapper` rather than adding a `TaskDTOV2` — verified against a real
/// instance's `/api/v2/openapi.json`: every field `TaskDTO` decodes has the
/// same name and type in v2's `Task`/`TaskReadOneBody` schemas, including
/// `due_date`/`start_date`/`end_date` still using Go's zero-value sentinel
/// for "unset" rather than `null` (same as v1 — `TaskMapper.dueDate(from:)`
/// needs no changes), and `labels`/`related_tasks`/`assignees` still
/// documented read-only via their own endpoints (matches `TaskDTO.labels`'s
/// existing doc comment on why `TaskMapper` never writes them).
///
/// `update(_:)` keeps v1's GET-then-merge-then-`PUT` "safe update" pattern
/// (`TaskMapper.merge`) rather than switching to v2's `PATCH`
/// (`application/merge-patch+json`), even though `PATCH` is available:
/// `TaskMapper.toDTO`/`.merge` rely on Swift's `Codable` synthesis omitting
/// `nil` optional fields from the request body, which is exactly right for
/// `PUT`'s full-replace semantics (an omitted field resets to zero/null,
/// matching what `TaskMapper.merge` intentionally fills in) but wrong for
/// `PATCH`'s JSON Merge Patch semantics, where an omitted field means
/// "leave unchanged" and an explicit `null` means "clear it" — reusing the
/// same DTO as-is would silently fail to clear a task's `description` or
/// `dueDate` from the app, since Swift would omit rather than null them.
/// Doing this correctly needs a body type that distinguishes "absent" from
/// "explicit null", which is its own follow-up, not bundled into this
/// migration.
public final class VikunjaTaskRepositoryV2: TaskRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        let envelope: APIv2Envelope<TaskDTO> = try await client.send(VikunjaEndpoints.tasksV2(projectID: projectID))
        return envelope.items.map(TaskMapper.toDomain)
    }

    public func fetchTask(id: Int) async throws -> VikunjaTask {
        let dto: TaskDTO = try await client.send(VikunjaEndpoints.taskV2(id: id))
        return TaskMapper.toDomain(dto)
    }

    public func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        let endpoint = try VikunjaEndpoints.createTaskV2(projectID: task.projectID, dto: TaskMapper.toDTO(task))
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    public func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        let current: TaskDTO = try await client.send(VikunjaEndpoints.taskV2(id: task.id))
        let endpoint = try VikunjaEndpoints.updateTaskV2(id: task.id, dto: TaskMapper.merge(task, onto: current))
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    public func delete(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteTaskV2(id: id))
    }

    public func searchTasks(query: String) async throws -> [VikunjaTask] {
        let envelope: APIv2Envelope<TaskDTO> = try await client.send(VikunjaEndpoints.searchTasksV2(query: query))
        return envelope.items.map(TaskMapper.toDomain)
    }
}
