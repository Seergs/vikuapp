import Foundation
@testable import VikunjaCore

/// Shared by `WebhookSyncCoordinatorTests`.
final class FakeWebhookRepository: WebhookRepositoryProtocol, @unchecked Sendable {
    struct CreatedUserWebhook {
        let targetURL: URL
        let events: [WebhookEvent]
        let secret: String?
    }

    struct CreatedProjectWebhook {
        let projectID: Int
        let targetURL: URL
        let events: [WebhookEvent]
        let secret: String?
    }

    private(set) var userWebhooks: [Webhook]
    private(set) var projectWebhooks: [Int: [Webhook]]
    private var nextID = 1000

    var createdUserWebhooks: [CreatedUserWebhook] = []
    var createdProjectWebhooks: [CreatedProjectWebhook] = []
    var updatedUserWebhooks: [Webhook] = []
    var updatedProjectWebhooks: [(projectID: Int, webhook: Webhook)] = []
    var deletedUserWebhookIDs: [Int] = []
    var deletedProjectWebhookIDs: [(projectID: Int, webhookID: Int)] = []

    init(userWebhooks: [Webhook] = [], projectWebhooks: [Int: [Webhook]] = [:]) {
        self.userWebhooks = userWebhooks
        self.projectWebhooks = projectWebhooks
    }

    func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        projectWebhooks[projectID] ?? []
    }

    func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        createdProjectWebhooks.append(
            CreatedProjectWebhook(projectID: projectID, targetURL: targetURL, events: events, secret: secret),
        )
        let webhook = Webhook(id: nextID, targetURL: targetURL, events: events, projectID: projectID)
        nextID += 1
        projectWebhooks[projectID, default: []].append(webhook)
        return webhook
    }

    func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        updatedProjectWebhooks.append((projectID, webhook))
        if let index = projectWebhooks[projectID]?.firstIndex(where: { $0.id == webhook.id }) {
            projectWebhooks[projectID]?[index] = webhook
        }
        return webhook
    }

    func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        deletedProjectWebhookIDs.append((projectID, webhookID))
        projectWebhooks[projectID]?.removeAll { $0.id == webhookID }
    }

    func fetchAvailableEvents() async throws -> [WebhookEvent] {
        Array(WebhookEvent.allCases.filter { !WebhookEvent.userDirected.contains($0) })
    }

    func fetchUserWebhooks() async throws -> [Webhook] {
        userWebhooks
    }

    func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        createdUserWebhooks.append(CreatedUserWebhook(targetURL: targetURL, events: events, secret: secret))
        let webhook = Webhook(id: nextID, targetURL: targetURL, events: events, userID: 1)
        nextID += 1
        userWebhooks.append(webhook)
        return webhook
    }

    func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        updatedUserWebhooks.append(webhook)
        if let index = userWebhooks.firstIndex(where: { $0.id == webhook.id }) {
            userWebhooks[index] = webhook
        }
        return webhook
    }

    func deleteUserWebhook(webhookID: Int) async throws {
        deletedUserWebhookIDs.append(webhookID)
        userWebhooks.removeAll { $0.id == webhookID }
    }

    func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        Array(WebhookEvent.userDirected)
    }
}
