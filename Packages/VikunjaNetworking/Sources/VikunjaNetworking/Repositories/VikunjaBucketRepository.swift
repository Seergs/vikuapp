import Foundation
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
        try await downloadBoard(projectID: projectID, viewID: nil).buckets
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        let view = try await kanbanView(projectID: projectID, viewID: viewID)
        var accumulated: [Int: BucketDTO] = [:]
        var tasks: [Int: [TaskDTO]] = [:]
        var page = 1
        while true {
            let response: BucketsWithTasksResponseDTO = try await client.send(
                VikunjaEndpoints.bucketsWithTasksV2(projectID: projectID, viewID: view.id, page: page),
            )
            guard Set(response.items.map(\.id)).count == response.items.count,
                  page == 1 || Set(response.items.map(\.id)) == Set(accumulated.keys)
            else { throw VikunjaError.decoding("Inconsistent Kanban bucket pages") }
            var complete = true
            for bucket in response.items {
                let previous = tasks[bucket.id] ?? []
                let incoming = bucket.tasks ?? []
                guard bucket.projectViewID == nil || bucket.projectViewID == view.id,
                      let count = bucket.count, count >= 0,
                      accumulated[bucket.id]?.count == nil || accumulated[bucket.id]?.count == count,
                      Set((previous + incoming).map(\.id)).count == previous.count + incoming.count,
                      previous.count + incoming.count <= count
                else { throw VikunjaError.decoding("Inconsistent Kanban task page") }
                accumulated[bucket.id] = bucket
                tasks[bucket.id] = previous + incoming
                if previous.count + incoming.count < count {
                    guard !incoming.isEmpty else { throw VikunjaError.decoding("Incomplete Kanban task page") }
                    complete = false
                }
            }
            if complete {
                break
            }
            page += 1
        }
        let buckets = accumulated.values.sorted {
            ($0.position ?? 0, $0.id) < ($1.position ?? 0, $1.id)
        }.map { bucket in
            KanbanBucket(
                id: bucket.id, title: bucket.title, isDoneBucket: bucket.id == view.doneBucketId,
                limit: bucket.limit, tasks: (tasks[bucket.id] ?? []).map(TaskMapper.toDomain),
            )
        }
        // Preserve a nonempty view filter as opaque JSON; no local DSL evaluation.
        var filterQuery = ""
        if case let .object(filter) = view.filter,
           filter["filter"] != nil || filter["s"] != nil {
            let hasFilter = filter["filter"] != nil && filter["filter"] != .string("") && filter["filter"] != .null
            let hasSearch = filter["s"] != nil && filter["s"] != .string("") && filter["s"] != .null
            if hasFilter || hasSearch {
                let encoded = try JSONEncoder().encode(view.filter)
                filterQuery = String(data: encoded, encoding: .utf8) ?? "unsupported"
            }
        }
        return KanbanDownload(
            viewID: view.id, mode: view.bucketConfigurationMode ?? "none", filterQuery: filterQuery,
            defaultBucketID: view.defaultBucketId, doneBucketID: view.doneBucketId, buckets: buckets,
        )
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
            task: task,
        )
        let dto: TaskDTO = try await client.send(endpoint)
        return TaskMapper.toDomain(dto)
    }

    private func kanbanView(projectID: Int, viewID: Int? = nil) async throws -> ProjectViewDTO {
        var page = 1
        while true {
            let envelope: APIv2Envelope<ProjectViewDTO> = try await client.send(
                VikunjaEndpoints.projectViewsV2(projectID: projectID, page: page),
            )
            if let view = envelope.items.first(where: {
                $0.viewKind == "kanban" && (viewID == nil || $0.id == viewID)
            }) {
                return view
            }
            guard page < envelope.totalPages else { throw VikunjaError.notFound }
            guard !envelope.items.isEmpty else { throw VikunjaError.decoding("Incomplete Kanban view list") }
            page += 1
        }
    }
}
