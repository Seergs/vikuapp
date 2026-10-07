/// Composes the OS permission prompt, the APNs device-token handshake, and
/// the relay registration (`PushRegistrationProviding`) behind one seam a
/// `Features/*` view model can depend on without importing UIKit or any
/// concrete networking type. The composition root wires the concrete
/// implementation (UIKit-bound permission/token handling plus a
/// `PushRegistrationProviding`) in the app target, since neither belongs in
/// VikunjaCore.
public protocol PushNotificationRegistering: Sendable {
    /// Requests notification authorization, and on success registers this
    /// device with the relay for `vikunjaUserID`. Returns `nil` when the
    /// user denies (or has previously denied) authorization — the caller
    /// must leave the feature off and explain how to re-enable it from the
    /// system Settings app, rather than retrying.
    func enable(vikunjaUserID: Int) async throws -> PushRegistration?

    /// Unregisters this device from the relay. Callers are still
    /// responsible for deleting the Vikunja webhooks themselves
    /// (`WebhookSyncing`).
    func disable() async throws
}
