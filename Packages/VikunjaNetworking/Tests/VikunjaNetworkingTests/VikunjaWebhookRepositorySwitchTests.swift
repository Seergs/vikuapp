import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaWebhookRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyWebhookRepository(label: "v1")
        let v2 = SpyWebhookRepository(label: "v2")
        let capabilityProvider = FakeWebhookCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaWebhookRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let webhooks = try await repository.fetchWebhooks(projectID: 4)

        #expect(webhooks.first?.targetURL.host == "v1")
        #expect(v1.fetchWebhooksCallCount == 1)
        #expect(v2.fetchWebhooksCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyWebhookRepository(label: "v1")
        let v2 = SpyWebhookRepository(label: "v2")
        let capabilityProvider = FakeWebhookCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaWebhookRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let webhooks = try await repository.fetchWebhooks(projectID: 4)

        #expect(webhooks.first?.targetURL.host == "v2")
        #expect(v1.fetchWebhooksCallCount == 0)
        #expect(v2.fetchWebhooksCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every project level method`() async throws {
        let v1 = SpyWebhookRepository(label: "v1")
        let v2 = SpyWebhookRepository(label: "v2")
        let capabilityProvider = FakeWebhookCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaWebhookRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)
        let targetURL = try #require(URL(string: "https://relay.viku.app/h/x"))

        _ = try await repository.createWebhook(projectID: 4, targetURL: targetURL, events: [.taskCreated], secret: nil)
        _ = try await repository.updateWebhook(projectID: 4, SpyWebhookRepository.webhook(label: "v2"))
        try await repository.deleteWebhook(projectID: 4, webhookID: 1)
        _ = try await repository.fetchAvailableEvents()

        #expect(v1.createCallCount == 0)
        #expect(v1.updateCallCount == 0)
        #expect(v1.deleteCallCount == 0)
        #expect(v1.availableEventsCallCount == 0)
        #expect(v2.createCallCount == 1)
        #expect(v2.updateCallCount == 1)
        #expect(v2.deleteCallCount == 1)
        #expect(v2.availableEventsCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every user level method`() async throws {
        let v1 = SpyWebhookRepository(label: "v1")
        let v2 = SpyWebhookRepository(label: "v2")
        let capabilityProvider = FakeWebhookCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaWebhookRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)
        let targetURL = try #require(URL(string: "https://relay.viku.app/h/x"))

        _ = try await repository.fetchUserWebhooks()
        _ = try await repository.createUserWebhook(targetURL: targetURL, events: [.taskOverdue], secret: "s")
        _ = try await repository.updateUserWebhook(SpyWebhookRepository.webhook(label: "v1"))
        try await repository.deleteUserWebhook(webhookID: 1)
        _ = try await repository.fetchAvailableUserEvents()

        #expect(v1.fetchUserWebhooksCallCount == 1)
        #expect(v1.createUserCallCount == 1)
        #expect(v1.updateUserCallCount == 1)
        #expect(v1.deleteUserCallCount == 1)
        #expect(v1.availableUserEventsCallCount == 1)
        #expect(v2.fetchUserWebhooksCallCount == 0)
        #expect(v2.createUserCallCount == 0)
        #expect(v2.updateUserCallCount == 0)
        #expect(v2.deleteUserCallCount == 0)
        #expect(v2.availableUserEventsCallCount == 0)
    }
}

private final class SpyWebhookRepository: WebhookRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchWebhooksCallCount = 0
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var availableEventsCallCount = 0
    private(set) var fetchUserWebhooksCallCount = 0
    private(set) var createUserCallCount = 0
    private(set) var updateUserCallCount = 0
    private(set) var deleteUserCallCount = 0
    private(set) var availableUserEventsCallCount = 0

    init(label: String) {
        self.label = label
    }

    static func webhook(label: String) -> Webhook {
        Webhook(id: 1, targetURL: targetURL(label: label), events: [.taskCreated], projectID: 1)
    }

    private static func targetURL(label: String) -> URL {
        guard let url = URL(string: "https://\(label)/h") else {
            preconditionFailure("\(label) is a valid URL host")
        }
        return url
    }

    func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        fetchWebhooksCallCount += 1
        return [Self.webhook(label: label)]
    }

    func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        createCallCount += 1
        return Self.webhook(label: label)
    }

    func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        updateCallCount += 1
        return webhook
    }

    func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        deleteCallCount += 1
    }

    func fetchAvailableEvents() async throws -> [WebhookEvent] {
        availableEventsCallCount += 1
        return [.taskCreated]
    }

    func fetchUserWebhooks() async throws -> [Webhook] {
        fetchUserWebhooksCallCount += 1
        return [Self.webhook(label: label)]
    }

    func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        createUserCallCount += 1
        return Self.webhook(label: label)
    }

    func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        updateUserCallCount += 1
        return webhook
    }

    func deleteUserWebhook(webhookID: Int) async throws {
        deleteUserCallCount += 1
    }

    func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        availableUserEventsCallCount += 1
        return [.taskOverdue, .taskReminderFired]
    }
}

private struct FakeWebhookCapabilityProvider: CapabilityProvider {
    let supportsAPIV2: Bool

    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "2.4.0", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        switch feature {
        case .apiV2:
            supportsAPIV2
        default:
            false
        }
    }
}
