import Foundation

/// Project-level and user-level webhook CRUD. Update is deliberately
/// "resend the whole `Webhook`" (mirroring `LabelRepositoryProtocol.update`/
/// `ProjectRepositoryProtocol.update`) rather than a narrower
/// `events:`-only signature: the server treats `target_url`/`secret`/auth as
/// immutable after creation regardless of what's in the body, so round-tripping
/// the fetched `Webhook` (with its `events` mutated) is both simpler for
/// callers and never at risk of accidentally clearing a field the server
/// does honor.
public protocol WebhookRepositoryProtocol: Sendable {
    func fetchWebhooks(projectID: Int) async throws -> [Webhook]
    func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook
    func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook
    func deleteWebhook(projectID: Int, webhookID: Int) async throws
    /// The event names a project-level webhook may subscribe to.
    func fetchAvailableEvents() async throws -> [WebhookEvent]

    func fetchUserWebhooks() async throws -> [Webhook]
    func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook
    func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook
    func deleteUserWebhook(webhookID: Int) async throws
    /// The event names a user-level webhook may subscribe to — a subset of
    /// `fetchAvailableEvents()` (see `WebhookEvent.userDirected`).
    func fetchAvailableUserEvents() async throws -> [WebhookEvent]
}
