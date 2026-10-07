import Foundation
import VikunjaCore

public final class VikunjaWebhookRepository: WebhookRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        let dtos: [WebhookDTO] = try await client.send(VikunjaEndpoints.webhooks(projectID: projectID))
        return dtos.compactMap(WebhookMapper.toDomain)
    }

    public func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.createWebhook(
            projectID: projectID,
            dto: WebhookMapper.toCreateDTO(targetURL: targetURL, events: events, secret: secret),
        )
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.updateWebhook(
            projectID: projectID,
            webhookID: webhook.id,
            dto: WebhookMapper.toDTO(webhook),
        )
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteWebhook(projectID: projectID, webhookID: webhookID))
    }

    public func fetchAvailableEvents() async throws -> [WebhookEvent] {
        let names: [String]? = try await client.send(VikunjaEndpoints.webhookEvents())
        return WebhookMapper.toEvents(names)
    }

    public func fetchUserWebhooks() async throws -> [Webhook] {
        let dtos: [WebhookDTO] = try await client.send(VikunjaEndpoints.userWebhooks())
        return dtos.compactMap(WebhookMapper.toDomain)
    }

    public func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.createUserWebhook(
            dto: WebhookMapper.toCreateDTO(targetURL: targetURL, events: events, secret: secret),
        )
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        let endpoint = try VikunjaEndpoints.updateUserWebhook(webhookID: webhook.id, dto: WebhookMapper.toDTO(webhook))
        let dto: WebhookDTO = try await client.send(endpoint)
        return try WebhookMapper.toDomainOrThrow(dto)
    }

    public func deleteUserWebhook(webhookID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteUserWebhook(webhookID: webhookID))
    }

    public func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        let names: [String]? = try await client.send(VikunjaEndpoints.userWebhookEvents())
        return WebhookMapper.toEvents(names)
    }
}
