import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct WebhookDTOTests {
    @Test
    func `decodes realistic project webhooks payload`() throws {
        let dtos = try loadDTOs(resource: "webhooks")

        #expect(dtos.count == 2)
        #expect(dtos[0].targetURL == "https://relay.viku.app/h/abc123")
        #expect(dtos[0].events == ["task.created", "task.updated", "task.deleted"])
        #expect(dtos[0].projectID == 4)
        #expect(dtos[0].userID == 0)
    }

    @Test
    func `maps project webhooks to domain, normalizing the unused scope ID to nil`() throws {
        let dtos = try loadDTOs(resource: "webhooks")
        let webhooks = dtos.compactMap(WebhookMapper.toDomain)

        #expect(webhooks.count == 2)
        #expect(webhooks[0].projectID == 4)
        #expect(webhooks[0].userID == nil)
        #expect(webhooks[1].events == [.taskCommentCreated])
    }

    @Test
    func `decodes realistic user webhooks payload`() throws {
        let dtos = try loadDTOs(resource: "user-webhooks")

        #expect(dtos.count == 1)
        #expect(dtos[0].projectID == 0)
        #expect(dtos[0].userID == 3)
    }

    /// The acceptance criterion this ticket calls out explicitly: the two
    /// user-directed event names this app relies on for push notifications
    /// (`VIKU-178`/`docs/PUSH_NOTIFICATIONS.md`) must round-trip exactly as
    /// Vikunja's Swagger/OpenAPI spec names them.
    @Test
    func `maps user webhooks to domain with the exact overdue and reminder event names`() throws {
        let dtos = try loadDTOs(resource: "user-webhooks")
        let webhooks = dtos.compactMap(WebhookMapper.toDomain)

        #expect(webhooks[0].userID == 3)
        #expect(webhooks[0].projectID == nil)
        #expect(webhooks[0].events == [.taskOverdue, .taskReminderFired])
        #expect(webhooks[0].events.map(\.rawValue) == ["task.overdue", "task.reminder.fired"])
    }

    @Test
    func `decodes the project level available events list`() throws {
        let names = try loadEventNames(resource: "webhook-events")
        let events = WebhookMapper.toEvents(names)

        #expect(events.count == 16)
        #expect(events.contains(.taskCreated))
        #expect(events.contains(.projectSharedTeam))
        // Project-level events never include the two user-directed ones.
        #expect(!events.contains(.taskOverdue))
    }

    @Test
    func `decodes the user level available events list as exactly the two user-directed events`() throws {
        let names = try loadEventNames(resource: "user-webhook-events")
        let events = WebhookMapper.toEvents(names)

        #expect(Set(events) == WebhookEvent.userDirected)
    }

    @Test
    func `drops an unrecognized event name rather than failing the whole decode`() {
        let events = WebhookMapper.toEvents(["task.created", "task.some_future_event"])

        #expect(events == [.taskCreated])
    }

    @Test
    func `round trips a create request through toCreateDTO and toDomain`() throws {
        let targetURL = try #require(URL(string: "https://relay.viku.app/h/round-trip"))
        let dto = WebhookMapper.toCreateDTO(targetURL: targetURL, events: [.taskOverdue], secret: "shh")

        #expect(dto.id == 0)
        #expect(dto.secret == "shh")
        #expect(dto.projectID == nil)
        #expect(dto.userID == nil)

        let webhook = try #require(WebhookMapper.toDomain(dto))
        #expect(webhook.targetURL == targetURL)
        #expect(webhook.events == [.taskOverdue])
    }

    private func loadDTOs(resource: String) throws -> [WebhookDTO] {
        let url = try #require(Bundle.module.url(forResource: resource, withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([WebhookDTO].self, from: data)
    }

    private func loadEventNames(resource: String) throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: resource, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String].self, from: data)
    }
}
