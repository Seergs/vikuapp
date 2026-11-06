import VikunjaCore

/// Transport for the modern bulk contract on both API versions. This is kept
/// separate from full task updates so sync can submit completion intents without
/// fetching or replacing each task. The local queue is wired independently.
public final class VikunjaTaskBulkCompletionRepository: TaskBulkCompletionRepositoryProtocol {
    private let client: APIClient
    private let capabilityProvider: CapabilityProvider

    public init(client: APIClient, capabilityProvider: CapabilityProvider) {
        self.client = client
        self.capabilityProvider = capabilityProvider
    }

    public func setCompletion(taskIDs: [EntityID], isDone: Bool) async throws -> [VikunjaTask] {
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
        let dto = TaskBulkCompletionRequestDTO(taskIDs: remoteIDs, isDone: isDone)
        let endpoint = try await capabilityProvider.supports(.apiV2)
            ? VikunjaEndpoints.setTaskBulkCompletionV2(dto: dto)
            : VikunjaEndpoints.setTaskBulkCompletion(dto: dto)
        let response: TaskBulkCompletionResponseDTO = try await client.send(endpoint)
        // Never let a truncated, duplicate or unrelated response acknowledge
        // mutations which the server has not actually returned to the caller.
        guard response.tasks.count == remoteIDs.count, Set(response.tasks.map(\.id)) == seen else {
            throw VikunjaError.decoding("Bulk completion response does not match the requested task IDs.")
        }
        return response.tasks.map(TaskMapper.toDomain)
    }
}
