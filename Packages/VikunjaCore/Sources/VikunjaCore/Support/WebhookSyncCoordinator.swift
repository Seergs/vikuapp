/// Reconciles a server's webhooks to a `NotificationSettings`: fetches
/// what's currently there, diffs it via `WebhookSyncing`, and applies
/// whatever the diff calls for through `WebhookRepositoryProtocol`. Shared
/// by every caller that needs this — `Features/Settings`' notifications
/// screen (user-triggered, on a toggle) and the composition root's
/// launch-time sync (automatic, no screen involved) — so the create/
/// update/delete logic has exactly one implementation.
public struct WebhookSyncCoordinator: Sendable {
    private let webhookRepository: WebhookRepositoryProtocol
    private let syncPlanner: WebhookSyncing

    public init(webhookRepository: WebhookRepositoryProtocol, syncPlanner: WebhookSyncing = WebhookSyncPlanner()) {
        self.webhookRepository = webhookRepository
        self.syncPlanner = syncPlanner
    }

    /// Fetches the user-level and every one of `projects`' webhooks,
    /// computes the plan `settings`/`registration` call for, and applies
    /// it. Throws on the first failed request — a partially applied plan
    /// is still a step toward matching `settings`, never further from it,
    /// so there's nothing to roll back.
    public func sync(settings: NotificationSettings, registration: PushRegistration, projects: [Project]) async throws {
        let userWebhooks = try await webhookRepository.fetchUserWebhooks()
        var projectWebhooks: [Int: [Webhook]] = [:]
        for project in projects {
            projectWebhooks[project.id] = try await webhookRepository.fetchWebhooks(projectID: project.id)
        }

        let plan = syncPlanner.plan(
            settings: settings,
            registration: registration,
            existingUserWebhooks: userWebhooks,
            existingProjectWebhooks: projectWebhooks,
        )
        try await apply(plan, registration: registration, userWebhooks: userWebhooks, projectWebhooks: projectWebhooks)
    }

    private func apply(
        _ plan: WebhookSyncPlan,
        registration: PushRegistration,
        userWebhooks: [Webhook],
        projectWebhooks: [Int: [Webhook]],
    ) async throws {
        for create in plan.creates {
            switch create.scope {
            case .user:
                _ = try await webhookRepository.createUserWebhook(
                    targetURL: registration.targetURL,
                    events: create.events,
                    secret: registration.secret,
                )
            case let .project(projectID):
                _ = try await webhookRepository.createWebhook(
                    projectID: projectID,
                    targetURL: registration.targetURL,
                    events: create.events,
                    secret: registration.secret,
                )
            }
        }

        for update in plan.updates {
            switch update.scope {
            case .user:
                guard var webhook = userWebhooks.first(where: { $0.id == update.webhookID }) else { continue }
                webhook.events = update.events
                _ = try await webhookRepository.updateUserWebhook(webhook)
            case let .project(projectID):
                guard var webhook = projectWebhooks[projectID]?.first(where: { $0.id == update.webhookID }) else {
                    continue
                }
                webhook.events = update.events
                _ = try await webhookRepository.updateWebhook(projectID: projectID, webhook)
            }
        }

        for delete in plan.deletes {
            switch delete.scope {
            case .user:
                try await webhookRepository.deleteUserWebhook(webhookID: delete.webhookID)
            case let .project(projectID):
                try await webhookRepository.deleteWebhook(projectID: projectID, webhookID: delete.webhookID)
            }
        }
    }
}
