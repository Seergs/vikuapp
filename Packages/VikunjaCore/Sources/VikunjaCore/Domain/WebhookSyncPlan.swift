/// The create/update/delete operations `WebhookSyncing` computes to make a
/// server's webhooks match a `NotificationSettings` — the output of a pure
/// diff, with no indication of whether (or in what order) a caller has
/// applied it yet.
public struct WebhookSyncPlan: Equatable, Sendable {
    public struct Create: Equatable, Sendable {
        public let scope: WebhookScope
        public let events: [WebhookEvent]

        public init(scope: WebhookScope, events: [WebhookEvent]) {
            self.scope = scope
            self.events = events
        }
    }

    public struct Update: Equatable, Sendable {
        public let scope: WebhookScope
        public let webhookID: Int
        public let events: [WebhookEvent]

        public init(scope: WebhookScope, webhookID: Int, events: [WebhookEvent]) {
            self.scope = scope
            self.webhookID = webhookID
            self.events = events
        }
    }

    public struct Delete: Equatable, Sendable {
        public let scope: WebhookScope
        public let webhookID: Int

        public init(scope: WebhookScope, webhookID: Int) {
            self.scope = scope
            self.webhookID = webhookID
        }
    }

    public let creates: [Create]
    public let updates: [Update]
    public let deletes: [Delete]

    public init(creates: [Create] = [], updates: [Update] = [], deletes: [Delete] = []) {
        self.creates = creates
        self.updates = updates
        self.deletes = deletes
    }

    public var isEmpty: Bool {
        creates.isEmpty && updates.isEmpty && deletes.isEmpty
    }
}
