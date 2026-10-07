import Foundation

/// Registers/unregisters this device with the relay (`relay.viku.app`, not
/// Vikunja itself — see `docs/PUSH_NOTIFICATIONS.md`). The concrete
/// implementation talks HTTP to the relay and APNs device-token handling,
/// neither of which belongs in VikunjaCore; this protocol is only the seam
/// `WebhookSyncing` and the composition root need.
public protocol PushRegistrationProviding: Sendable {
    /// Registers `deviceToken` (the raw token APNs handed the app) with the
    /// relay, returning where this device's Vikunja webhooks should point
    /// and the secret to create them with. Safe to call again with a
    /// refreshed token — the relay is expected to treat it as an upsert.
    func register(deviceToken: Data) async throws -> PushRegistration

    /// Unregisters this device from the relay, e.g. when the user disables
    /// notifications. Callers are still responsible for deleting the
    /// Vikunja webhooks themselves (`WebhookSyncing`) — this only tells the
    /// relay to stop expecting deliveries for this device.
    func unregister() async throws
}
