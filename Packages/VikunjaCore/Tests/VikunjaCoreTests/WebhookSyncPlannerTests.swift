import Foundation
import Testing
@testable import VikunjaCore

@Suite("WebhookSyncPlanner")
struct WebhookSyncPlannerTests {
    private let registration = PushRegistration(
        targetURL: URL(string: "https://relay.viku.app/h/device-1")!,
        secret: "shh",
    )
    private let someoneElsesWebhook = Webhook(
        id: 99,
        targetURL: URL(string: "https://example.com/some-other-integration")!,
        events: [.taskCreated],
    )
    /// A deterministic ordering of `WebhookEvent.userDirected`, matching
    /// what `WebhookSyncPlanner` itself produces (alphabetical by raw
    /// value) — used to build a "no change needed" fixture webhook.
    private let sortedUserDirectedEvents = WebhookEvent.userDirected.sorted { $0.rawValue < $1.rawValue }

    // MARK: disabled

    @Test
    func `disabled settings delete this device's user webhook and leave others untouched`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: false)
        let ours = Webhook(id: 1, targetURL: registration.targetURL, events: sortedUserDirectedEvents)

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [ours, someoneElsesWebhook],
            existingProjectWebhooks: [:],
        )

        #expect(plan.creates.isEmpty)
        #expect(plan.updates.isEmpty)
        #expect(plan.deletes == [WebhookSyncPlan.Delete(scope: .user, webhookID: 1)])
    }

    @Test
    func `disabled settings delete every enabled project's webhook`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: false, projectEvents: [4: [.taskCreated]])
        let ours = Webhook(id: 2, targetURL: registration.targetURL, events: [.taskCreated], projectID: 4)

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [4: [ours]],
        )

        #expect(plan.deletes == [WebhookSyncPlan.Delete(scope: .project(4), webhookID: 2)])
    }

    @Test
    func `disabled settings with nothing on the server produce an empty plan`() {
        let planner = WebhookSyncPlanner()
        let plan = planner.plan(
            settings: NotificationSettings(isEnabled: false),
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [:],
        )

        #expect(plan.isEmpty)
    }

    // MARK: user-level

    @Test
    func `enabling user level with no existing webhook creates one with the user directed events`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: WebhookEvent.userDirected)

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [:],
        )

        #expect(plan.creates.count == 1)
        #expect(plan.creates[0].scope == .user)
        #expect(Set(plan.creates[0].events) == WebhookEvent.userDirected)
        #expect(plan.updates.isEmpty)
        #expect(plan.deletes.isEmpty)
    }

    @Test
    func `an already correct user webhook needs no change`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: WebhookEvent.userDirected)
        let ours = Webhook(id: 1, targetURL: registration.targetURL, events: sortedUserDirectedEvents)

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [ours],
            existingProjectWebhooks: [:],
        )

        #expect(plan.isEmpty)
    }

    @Test
    func `turning user level off deletes this device's webhook but leaves someone else's alone`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: true, userLevelEvents: [])
        let ours = Webhook(id: 1, targetURL: registration.targetURL, events: [.taskOverdue, .taskReminderFired])

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [ours, someoneElsesWebhook],
            existingProjectWebhooks: [:],
        )

        #expect(plan.deletes == [WebhookSyncPlan.Delete(scope: .user, webhookID: 1)])
    }

    // MARK: project-level

    @Test
    func `enabling a project with no existing webhook creates one with the configured events`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(
            isEnabled: true,
            projectEvents: [4: [.taskCreated]],
        )

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [:],
        )

        #expect(plan.creates == [WebhookSyncPlan.Create(scope: .project(4), events: [.taskCreated])])
    }

    @Test
    func `changing the enabled event set updates the existing project webhook`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(
            isEnabled: true,
            projectEvents: [4: [.taskDeleted]],
        )
        let ours = Webhook(id: 3, targetURL: registration.targetURL, events: [.taskCreated], projectID: 4)

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [4: [ours]],
        )

        #expect(plan.updates == [WebhookSyncPlan.Update(scope: .project(4), webhookID: 3, events: [.taskDeleted])])
    }

    @Test
    func `disabling one project deletes only that project's webhook`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: true, projectEvents: [5: [.taskCreated]])
        let project4Webhook = Webhook(id: 3, targetURL: registration.targetURL, events: [.taskCreated], projectID: 4)
        let project5Webhook = Webhook(
            id: 4,
            targetURL: registration.targetURL,
            events: [.taskCreated],
            projectID: 5,
        )

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [4: [project4Webhook], 5: [project5Webhook]],
        )

        #expect(plan.deletes == [WebhookSyncPlan.Delete(scope: .project(4), webhookID: 3)])
        #expect(plan.creates.isEmpty)
        #expect(plan.updates.isEmpty)
    }

    @Test
    func `a project webhook belonging to another device is never touched`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(isEnabled: true)
        let someoneElsesProjectWebhook = Webhook(
            id: 10,
            targetURL: someoneElsesWebhook.targetURL,
            events: [.taskCreated],
            projectID: 4,
        )

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [4: [someoneElsesProjectWebhook]],
        )

        #expect(plan.isEmpty)
    }

    @Test
    func `reconciles several projects at once, each independently`() {
        let planner = WebhookSyncPlanner()
        let settings = NotificationSettings(
            isEnabled: true,
            projectEvents: [1: [.taskCreated], 2: [.taskCreated]],
        )
        let project2Webhook = Webhook(id: 20, targetURL: registration.targetURL, events: [.taskCreated], projectID: 2)
        let project3Webhook = Webhook(id: 30, targetURL: registration.targetURL, events: [.taskCreated], projectID: 3)

        let plan = planner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: [],
            existingProjectWebhooks: [2: [project2Webhook], 3: [project3Webhook]],
        )

        #expect(plan.creates == [WebhookSyncPlan.Create(scope: .project(1), events: [.taskCreated])])
        #expect(plan.updates.isEmpty)
        #expect(plan.deletes == [WebhookSyncPlan.Delete(scope: .project(3), webhookID: 30)])
    }
}
