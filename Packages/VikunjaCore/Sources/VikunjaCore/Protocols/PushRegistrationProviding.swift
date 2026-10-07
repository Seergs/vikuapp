import Foundation

/// Registers/unregisters this device with the relay (`relay.viku.dev`, not
/// Vikunja itself). The concrete implementation talks HTTP to the relay and
/// APNs device-token handling, neither of which belongs in VikunjaCore; this
/// protocol is only the seam `WebhookSyncing` and the composition root need.
public protocol PushRegistrationProviding: Sendable {
    /// Registers `deviceToken` (the raw token APNs handed the app) with the
    /// relay, returning where this device's Vikunja webhooks should point
    /// and the secret to create them with. `vikunjaUserID` is the signed-in
    /// account's numeric Vikunja user id, which the relay uses only to drop
    /// self-caused project events — it never verifies it against Vikunja.
    /// Safe to call again with a refreshed token or a different user id —
    /// the relay treats registration as an upsert keyed by the device token.
    func register(deviceToken: Data, vikunjaUserID: Int) async throws -> PushRegistration

    /// Unregisters this device from the relay, e.g. when the user disables
    /// notifications. Callers are still responsible for deleting the
    /// Vikunja webhooks themselves (`WebhookSyncing`) — this only tells the
    /// relay to stop expecting deliveries for this device.
    func unregister() async throws
}
