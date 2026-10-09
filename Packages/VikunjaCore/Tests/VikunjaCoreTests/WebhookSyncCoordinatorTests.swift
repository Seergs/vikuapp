import Foundation
import Testing
@testable import VikunjaCore

@Suite("WebhookSyncCoordinator")
struct WebhookSyncCoordinatorTests {
    private let registration = PushRegistration(
        targetURL: URL(string: "https://relay.example.com/h/device-1")!,
        secret: "shh",
    )

    @Test
    func `creates the user webhook when none exists and one is desired`() async throws {
        let repository = FakeWebhookRepository()
        let coordinator = WebhookSyncCoordinator(webhookRepository: repository)
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: WebhookEvent.userDirected)

        try await coordinator.sync(settings: settings, registration: registration, projects: [])

        #expect(repository.createdUserWebhooks.count == 1)
        #expect(repository.createdUserWebhooks[0].targetURL == registration.targetURL)
        #expect(repository.createdUserWebhooks[0].secret == "shh")
        #expect(Set(repository.createdUserWebhooks[0].events) == WebhookEvent.userDirected)
    }

    @Test
    func `creates a project webhook with the configured events`() async throws {
        let project = Project(id: 4, title: "Work")
        let repository = FakeWebhookRepository()
        let coordinator = WebhookSyncCoordinator(webhookRepository: repository)
        let settings = NotificationSettings(
            isEnabled: true,
            projectEvents: [4: [.taskCreated]],
        )

        try await coordinator.sync(settings: settings, registration: registration, projects: [project])

        #expect(repository.createdProjectWebhooks.count == 1)
        #expect(repository.createdProjectWebhooks[0].projectID == 4)
        #expect(repository.createdProjectWebhooks[0].events == [.taskCreated])
    }

    @Test
    func `updates an existing webhook whose events no longer match`() async throws {
        let project = Project(id: 4, title: "Work")
        let existing = Webhook(id: 9, targetURL: registration.targetURL, events: [.taskCreated], projectID: 4)
        let repository = FakeWebhookRepository(projectWebhooks: [4: [existing]])
        let coordinator = WebhookSyncCoordinator(webhookRepository: repository)
        let settings = NotificationSettings(
            isEnabled: true,
            projectEvents: [4: [.taskDeleted]],
        )

        try await coordinator.sync(settings: settings, registration: registration, projects: [project])

        #expect(repository.updatedProjectWebhooks.count == 1)
        #expect(repository.updatedProjectWebhooks[0].webhook.events == [.taskDeleted])
        #expect(repository.createdProjectWebhooks.isEmpty)
    }

    @Test
    func `deletes a webhook that's no longer desired`() async throws {
        let existing = Webhook(id: 9, targetURL: registration.targetURL, events: [.taskOverdue, .taskReminderFired])
        let repository = FakeWebhookRepository(userWebhooks: [existing])
        let coordinator = WebhookSyncCoordinator(webhookRepository: repository)
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: [])

        try await coordinator.sync(settings: settings, registration: registration, projects: [])

        #expect(repository.deletedUserWebhookIDs == [9])
    }

    @Test
    func `a webhook that already matches is left untouched`() async throws {
        let sorted = WebhookEvent.userDirected.sorted { $0.rawValue < $1.rawValue }
        let existing = Webhook(id: 9, targetURL: registration.targetURL, events: sorted)
        let repository = FakeWebhookRepository(userWebhooks: [existing])
        let coordinator = WebhookSyncCoordinator(webhookRepository: repository)
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: WebhookEvent.userDirected)

        try await coordinator.sync(settings: settings, registration: registration, projects: [])

        #expect(repository.createdUserWebhooks.isEmpty)
        #expect(repository.updatedUserWebhooks.isEmpty)
        #expect(repository.deletedUserWebhookIDs.isEmpty)
    }

    @Test
    func `a webhook belonging to another device is never touched`() async throws {
        let someoneElses = try Webhook(id: 9, targetURL: #require(URL(string: "https://relay.example.com/h/other-device")), events: [.taskCreated])
        let repository = FakeWebhookRepository(userWebhooks: [someoneElses])
        let coordinator = WebhookSyncCoordinator(webhookRepository: repository)
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: [])

        try await coordinator.sync(settings: settings, registration: registration, projects: [])

        #expect(repository.deletedUserWebhookIDs.isEmpty)
        #expect(repository.createdUserWebhooks.isEmpty)
    }
}
