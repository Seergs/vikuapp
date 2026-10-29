import VikunjaCore

/// v2-only implementation of `BucketRepositoryProtocol`. Kanban has never
/// shipped in this app before, so unlike every other v2-migrated resource
/// there is no v1 counterpart and no `...Switch` wrapper — gating happens at
/// the call site via `CapabilityProvider.supports(.apiV2)` instead.
///
/// Every method takes only a `projectID`; `kanbanView(projectID:)` resolves
/// the project's Kanban-kind view internally on each call rather than
/// caching it, since these are user-initiated actions (open board, drag a
/// card, add a task), not a hot loop.
final class VikunjaBucketRepository: BucketRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        let view = try await kanbanView(projectID: projectID)
        let endpoint = VikunjaEndpoints.bucketsWithTasksV2(projectID: projectID, viewID: view.id)
        let response: BucketsWithTasksResponseDTO = try await client.send(endpoint)
        var buckets = response.items.map { BucketMapper.toDomain($0, isDoneBucket: $0.id == view.doneBucketId) }
        var lastPage = response.items
        var page = 1
        // The envelope lists all columns, but `page` applies to the tasks
        // inside each column. Never infer a page size from the default.
        while lastPage.contains(where: { dto in
            guard let bucket = buckets.first(where: { $0.id == dto.id }) else { return false }
            return !(dto.tasks ?? []).isEmpty && bucket.tasks.count < (dto.count ?? bucket.tasks.count)
        }) {
            page += 1
            let next: BucketsWithTasksResponseDTO = try await client.send(
                VikunjaEndpoints.bucketsWithTasksV2(projectID: projectID, viewID: view.id, page: page),
            )
            for dto in next.items {
                guard let index = buckets.firstIndex(where: { $0.id == dto.id }) else { continue }
                buckets[index].tasks += (dto.tasks ?? []).map(TaskMapper.toDomain)
            }
            lastPage = next.items
        }
        return buckets
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int) async throws -> VikunjaTask {
        let view = try await kanbanView(projectID: projectID)
        let endpoint = try VikunjaEndpoints.moveTaskToBucketV2(
            projectID: projectID,
            viewID: view.id,
            bucketID: toBucketID,
            taskID: taskID,
        )
        let response: TaskBucketResponseDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(response.task)
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        let endpoint = try VikunjaEndpoints.createTaskInBucketV2(
            projectID: projectID,
            bucketID: bucketID,
            title: task.title,
        )
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    private func kanbanView(projectID: Int) async throws -> ProjectViewDTO {
        let envelope: APIv2Envelope<ProjectViewDTO> = try await client.send(
            VikunjaEndpoints.projectViewsV2(projectID: projectID),
        )
        guard let view = envelope.items.first(where: { $0.viewKind == "kanban" }) else {
            throw VikunjaError.notFound
        }
        return view
    }
}
