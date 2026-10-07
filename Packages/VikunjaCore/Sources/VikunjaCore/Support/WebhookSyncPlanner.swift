/// Default `WebhookSyncing`: diffs the desired state (`NotificationSettings`)
/// against what's already on the server, scope by scope. A scope's webhook
/// is recognized as "ours" by an exact `targetURL` match against
/// `registration` — this device's relay URL is unique (it embeds an opaque
/// device id), so this never touches a webhook some other client or a user
/// configured by hand.
public struct WebhookSyncPlanner: WebhookSyncing {
    private enum Action {
        case create([WebhookEvent])
        case update(webhookID: Int, events: [WebhookEvent])
        case delete(webhookID: Int)
    }

    public init() {}

    public func plan(
        settings: NotificationSettings,
        registration: PushRegistration,
        existingUserWebhooks: [Webhook],
        existingProjectWebhooks: [Int: [Webhook]],
    ) -> WebhookSyncPlan {
        var creates: [WebhookSyncPlan.Create] = []
        var updates: [WebhookSyncPlan.Update] = []
        var deletes: [WebhookSyncPlan.Delete] = []

        func apply(_ scope: WebhookScope, _ action: Action?) {
            switch action {
            case let .create(events):
                creates.append(WebhookSyncPlan.Create(scope: scope, events: events))
            case let .update(webhookID, events):
                updates.append(WebhookSyncPlan.Update(scope: scope, webhookID: webhookID, events: events))
            case let .delete(webhookID):
                deletes.append(WebhookSyncPlan.Delete(scope: scope, webhookID: webhookID))
            case nil:
                break
            }
        }

        apply(
            .user,
            reconcile(
                desiredEvents: settings.isEnabled && settings.userLevelEnabled ? WebhookEvent.userDirected : [],
                existing: existingUserWebhooks,
                registration: registration,
            ),
        )

        // Every project with an existing webhook needs to be considered for
        // deletion even if it's no longer (or never was) in
        // `enabledProjectIDs` — not just the ones currently desired.
        let enabledProjectIDs = settings.isEnabled ? settings.enabledProjectIDs : []
        let allProjectIDs = Set(existingProjectWebhooks.keys).union(enabledProjectIDs)
        for projectID in allProjectIDs.sorted() {
            apply(
                .project(projectID),
                reconcile(
                    desiredEvents: enabledProjectIDs.contains(projectID) ? settings.enabledProjectEvents : [],
                    existing: existingProjectWebhooks[projectID] ?? [],
                    registration: registration,
                ),
            )
        }

        return WebhookSyncPlan(creates: creates, updates: updates, deletes: deletes)
    }

    /// `nil` means this scope's webhook (if any) already matches `desiredEvents`.
    private func reconcile(
        desiredEvents: Set<WebhookEvent>,
        existing: [Webhook],
        registration: PushRegistration,
    ) -> Action? {
        let ours = existing.first { $0.targetURL == registration.targetURL }

        guard !desiredEvents.isEmpty else {
            return ours.map { .delete(webhookID: $0.id) }
        }

        guard let ours else {
            return .create(sorted(desiredEvents))
        }

        guard Set(ours.events) != desiredEvents else {
            return nil
        }
        return .update(webhookID: ours.id, events: sorted(desiredEvents))
    }

    /// Alphabetical by raw value, purely so `creates`/`updates` have a
    /// deterministic, test-friendly order rather than `Set`'s unspecified one.
    private func sorted(_ events: Set<WebhookEvent>) -> [WebhookEvent] {
        events.sorted { $0.rawValue < $1.rawValue }
    }
}
