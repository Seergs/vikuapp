import Foundation

/// Persists the user's configured Vikunja instance connections and tracks
/// which one is active. Implemented by a Keychain-backed store in
/// `VikuAuth` — account metadata and credentials must never live in
/// `UserDefaults`.
public protocol AccountStoreProtocol: Sendable {
    func fetchAccounts() async throws -> [InstanceAccount]
    func activeAccount() async throws -> InstanceAccount?

    /// Saves a new account with a verified positive user ID and makes it active.
    /// Existing IDs cannot be added again to bypass identity/session guards.
    func addAccount(_ account: InstanceAccount, token: String) async throws

    /// Updates an already-saved account's metadata in place, without changing
    /// which account is active. Production stores require `token` to be nil;
    /// explicit logins use replaceSession and automatic renewals use updateSession.
    /// Throws `VikunjaError.notFound` if
    /// `account.id` isn't a saved account.
    func updateAccount(_ account: InstanceAccount, token: String?) async throws

    /// Commits a verified explicit login only while the expected account/session still match.
    /// Stores serialize comparison and replacement with renewal and metadata updates.
    func replaceSession(
        _ account: InstanceAccount, token: String,
        expected: InstanceAccount, matchingToken: String?,
    ) async throws

    /// Commits a renewal only if the account and credential still match the
    /// request's snapshot. Implementations serialize the comparison and write
    /// with other account updates. A replaced/deleted session returns false.
    func updateSession(
        for account: InstanceAccount,
        matchingToken: String,
        token: String?,
        needsReauthentication: Bool,
    ) async throws -> Bool

    func removeAccount(id: InstanceAccount.ID) async throws
    func setActiveAccount(id: InstanceAccount.ID) async throws
    func token(forAccountID id: InstanceAccount.ID) async throws -> String?
}
