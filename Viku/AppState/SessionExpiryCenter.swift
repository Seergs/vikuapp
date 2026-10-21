import Observation
import VikunjaCore

/// Bridges `PasswordSessionRefresher`'s (`VikunjaNetworking`) notification
/// that an account's session can no longer be renewed into something
/// `MainTabView` can observe and react to — switch to the Settings tab and
/// prompt the user to sign in again. A protocol conformance rather than a
/// plain closure so `AppContainer` can hand the same instance to both the
/// app's own `sessionRefresher` and `refreshWidgetSnapshots()`'s resolver.
///
/// Doesn't persist anything itself: `InstanceAccount.needsReauthentication`
/// (in the Keychain, via `AccountStoreProtocol`) is the durable record, this
/// is only the live, in-process "something changed just now" signal for a
/// shell that's already on screen.
@MainActor
@Observable
final class SessionExpiryCenter: SessionExpiryReporting {
    /// The most recently flagged account, or `nil` once `MainTabView` has
    /// consumed it. Sees only account IDs — the app's single-account-shell
    /// design means "which account" is otherwise always implicit (whatever
    /// `MainTabView` is currently showing).
    private(set) var expiredAccountID: InstanceAccount.ID?

    nonisolated func reportSessionExpired(accountID: InstanceAccount.ID) async {
        await MainActor.run {
            expiredAccountID = accountID
        }
    }

    /// Called once `MainTabView` has reacted to `expiredAccountID`, so an
    /// unrelated re-render doesn't re-trigger the same prompt.
    func acknowledge() {
        expiredAccountID = nil
    }
}
