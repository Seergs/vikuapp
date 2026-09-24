/// Notified the moment a password/OIDC account's session is found to be
/// unrecoverable (its refresh token was itself rejected by the server) —
/// implemented by `PasswordSessionRefresher`'s caller in the composition
/// root, so the app shell can prompt the user to sign in again instead of
/// leaving every affected screen to fail silently on its own. A protocol
/// (rather than a concrete `@Observable` type) so `VikunjaNetworking` stays
/// decoupled from anything UI-flavored.
public protocol SessionExpiryReporting: Sendable {
    /// `accountID` is already persisted with `needsReauthentication == true`
    /// by the time this is called — this is a live notification on top of
    /// that, for a shell that's already on screen to react immediately
    /// rather than only on its next launch/appearance.
    func reportSessionExpired(accountID: InstanceAccount.ID) async
}
