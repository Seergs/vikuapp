import Foundation
import VikunjaCore

/// Routes each `WebhookRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource).
final class VikunjaWebhookRepositorySwitch: WebhookRepositoryProtocol {
    private let v1: WebhookRepositoryProtocol
    private let v2: WebhookRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: WebhookRepositoryProtocol, v2: WebhookRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> WebhookRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        try await resolve().fetchWebhooks(projectID: projectID)
    }

    func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        try await resolve().createWebhook(projectID: projectID, targetURL: targetURL, events: events, secret: secret)
    }

    func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        try await resolve().updateWebhook(projectID: projectID, webhook)
    }

    func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        try await resolve().deleteWebhook(projectID: projectID, webhookID: webhookID)
    }

    func fetchAvailableEvents() async throws -> [WebhookEvent] {
        try await resolve().fetchAvailableEvents()
    }

    func fetchUserWebhooks() async throws -> [Webhook] {
        try await resolve().fetchUserWebhooks()
    }

    func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        try await resolve().createUserWebhook(targetURL: targetURL, events: events, secret: secret)
    }

    func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        try await resolve().updateUserWebhook(webhook)
    }

    func deleteUserWebhook(webhookID: Int) async throws {
        try await resolve().deleteUserWebhook(webhookID: webhookID)
    }

    func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        try await resolve().fetchAvailableUserEvents()
    }
}
