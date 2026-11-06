import VikunjaCore

/// Transport for the modern bulk contract on both API versions. This is kept
/// separate from full task updates so sync can submit bulk intents without
/// fetching or replacing each task. The local queue is wired independently.
public final class VikunjaTaskBulkUpdateRepository: TaskBulkUpdateRepositoryProtocol {
    private let client: APIClient
    private let capabilityProvider: CapabilityProvider

    public init(client: APIClient, capabilityProvider: CapabilityProvider) {
        self.client = client
        self.capabilityProvider = capabilityProvider
    }

    public func apply(_ change: TaskBulkChange, toTaskIDs taskIDs: [EntityID]) async throws -> [VikunjaTask] {
        guard !taskIDs.isEmpty else { return [] }
        var seen: Set<Int> = []
        var remoteIDs: [Int] = []
        for taskID in taskIDs {
            // Reject the entire input before sending anything. Sync must resolve
            // local identities after their task creations reach the server.
            guard let remoteID = taskID.remoteValue, remoteID > 0 else {
                throw VikunjaError.notFound
            }
            if seen.insert(remoteID).inserted {
                remoteIDs.append(remoteID)
            }
        }
        let dto = TaskBulkUpdateRequestDTO(taskIDs: remoteIDs, change: change)
        let endpoint = try await capabilityProvider.supports(.apiV2)
            ? VikunjaEndpoints.updateTasksInBulkV2(dto: dto)
            : VikunjaEndpoints.updateTasksInBulk(dto: dto)
        let response: TaskBulkUpdateResponseDTO = try await client.send(endpoint)
        // Never let a truncated, duplicate or unrelated response acknowledge
        // mutations which the server has not actually returned to the caller.
        guard response.tasks.count == remoteIDs.count, Set(response.tasks.map(\.id)) == seen else {
            throw VikunjaError.decoding("Bulk update response does not match the requested task IDs.")
        }
        return response.tasks.map(TaskMapper.toDomain)
    }
}
