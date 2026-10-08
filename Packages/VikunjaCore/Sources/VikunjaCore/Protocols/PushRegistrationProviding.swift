import Foundation

/// Registers/unregisters this device with the relay (`relay.viku.dev`, not
/// Vikunja itself). The concrete implementation talks HTTP to the relay and
/// APNs device-token handling, neither of which belongs in VikunjaCore; this
/// protocol is only the seam `WebhookSyncing` and the composition root need.
public protocol PushRegistrationProviding: Sendable {
    /// Registers `deviceToken` (the raw token APNs handed the app) with the
    /// relay for `accountID`, returning where that account's Vikunja
    /// webhooks should point and the secret to create them with.
    /// `vikunjaUserID` is the signed-in account's numeric Vikunja user id,
    /// which the relay uses only to drop self-caused project events — it
    /// never verifies it against Vikunja.
    ///
    /// The relay's registration is keyed by `accountID`, not by
    /// `deviceToken`: one physical device can hold a separate registration
    /// per saved connection, each with its own webhook URL and secret, so
    /// enabling notifications on two accounts never collide. Safe to call
    /// again for the same `accountID` with a refreshed token or a different
    /// user id — the relay treats registration as an upsert keyed by the
    /// account.
    func register(deviceToken: Data, vikunjaUserID: Int, accountID: InstanceAccount.ID) async throws -> PushRegistration

    /// Unregisters `accountID` from the relay, e.g. when the user disables
    /// notifications for that account. Callers are still responsible for
    /// deleting that account's Vikunja webhooks themselves (`WebhookSyncing`)
    /// — this only tells the relay to stop expecting deliveries for it.
    /// Other accounts' registrations on this device are unaffected.
    func unregister(accountID: InstanceAccount.ID) async throws
}
