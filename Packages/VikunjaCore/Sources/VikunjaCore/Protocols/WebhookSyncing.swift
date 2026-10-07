/// Reconciles Vikunja's webhooks with a `NotificationSettings` — pure and
/// synchronous, so the policy of "what should change" is unit-testable with
/// no networking at all (this ticket's acceptance criterion). A caller
/// fetches `existingUserWebhooks`/`existingProjectWebhooks` via
/// `WebhookRepositoryProtocol` and later applies the returned plan through
/// the same protocol; neither of those I/O steps lives here.
public protocol WebhookSyncing: Sendable {
    /// - Parameters:
    ///   - settings: the desired state.
    ///   - registration: this device's relay registration — `targetURL` is
    ///     how a webhook already on the server is recognized as "ours"
    ///     versus something else configured on the instance.
    ///   - existingUserWebhooks: every webhook currently on the user-level
    ///     scope, as fetched from the server.
    ///   - existingProjectWebhooks: every webhook currently on each
    ///     project's scope, keyed by project ID, as fetched from the
    ///     server. A project absent from this dictionary is treated as
    ///     having no webhooks, the same as an empty array.
    func plan(
        settings: NotificationSettings,
        registration: PushRegistration,
        existingUserWebhooks: [Webhook],
        existingProjectWebhooks: [Int: [Webhook]],
    ) -> WebhookSyncPlan
}
