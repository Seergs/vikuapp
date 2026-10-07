import Foundation
import VikunjaCore

/// v2 implementation of `WebhookRepositoryProtocol`. Reuses v1's
/// `WebhookDTO`/`WebhookMapper` rather than adding a `WebhookDTOV2` —
/// verified against a real instance's `/api/v2/openapi.json`: the `Webhook`
/// schema is identical in both versions (same DB table), and the only
/// shape difference is list responses wrapping it in `PaginatedWebhook`.
public final class VikunjaWebhookRepositoryV2: WebhookRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        let endpoint = VikunjaEndpoints.webhooksV2(projectID: projectID)
        let envelope: APIv2Envelope<WebhookDTO> = try await client.send(endpoint)
        return envelope.items.compactMap(WebhookMapper.toDomain)
    }

    public func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.createWebhookV2(
            projectID: projectID,
            dto: WebhookMapper.toCreateDTO(targetURL: targetURL, events: events, secret: secret),
        )
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.updateWebhookV2(
            projectID: projectID,
            webhookID: webhook.id,
            dto: WebhookMapper.toDTO(webhook),
        )
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteWebhookV2(projectID: projectID, webhookID: webhookID))
    }

    public func fetchAvailableEvents() async throws -> [WebhookEvent] {
        let names: [String]? = try await client.send(VikunjaEndpoints.webhookEventsV2())
        return WebhookMapper.toEvents(names)
    }

    public func fetchUserWebhooks() async throws -> [Webhook] {
        let envelope: APIv2Envelope<WebhookDTO> = try await client.send(VikunjaEndpoints.userWebhooksV2())
        return envelope.items.compactMap(WebhookMapper.toDomain)
    }

    public func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.createUserWebhookV2(
            dto: WebhookMapper.toCreateDTO(targetURL: targetURL, events: events, secret: secret),
        )
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        let dto = WebhookMapper.toDTO(webhook)
        let endpoint = try VikunjaEndpoints.updateUserWebhookV2(webhookID: webhook.id, dto: dto)
        let responseDTO: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(responseDTO)
    }

    public func deleteUserWebhook(webhookID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteUserWebhookV2(webhookID: webhookID))
    }

    public func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        let names: [String]? = try await client.send(VikunjaEndpoints.userWebhookEventsV2())
        return WebhookMapper.toEvents(names)
    }
}
