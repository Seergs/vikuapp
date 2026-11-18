import Foundation
import VikunjaCore

/// Keychain-backed `AccountStoreProtocol`. Account metadata (id, display name,
/// base URL) and the active-account pointer are stored as JSON/plain strings;
/// each account's bearer token is stored as its own item, keyed by account id,
/// so removing an account can drop its secret without touching the others.
///
/// Pass `accessGroup` (a `keychain-access-group` shared by the app target and
/// its widget extension) to store everything in that shared group so the
/// widget process can read the active account and its token. Left `nil`, the
/// store behaves exactly as a single-process store.
public actor KeychainAccountStore: AccountStoreProtocol {
    private let service: String
    private let accessGroup: String?
    private let indexAccount = "instance-accounts-index"
    private let activeAccountItem = "active-account-id"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        service: String,
        accessGroup: String? = nil,
    ) {
        self.service = service
        self.accessGroup = accessGroup

        // This JSON never leaves the device (unlike the wire DTOs in
        // VikunjaNetworking, which use `.iso8601` to match the server). Dates
        // are encoded as the raw bit pattern of their underlying `Double` so
        // `createdAt` round-trips exactly — `.iso8601` truncates to whole
        // seconds, and `.secondsSince1970`/`.millisecondsSince1970` round-trip
        // the `Double` through JSON text, which loses precision.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate.bitPattern)
        }
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let bitPattern = try container.decode(UInt64.self)
            return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bitPattern))
        }
        self.decoder = decoder
    }

    public func fetchAccounts() throws -> [InstanceAccount] {
        try loadIndex()
    }

    public func activeAccount() throws -> InstanceAccount? {
        guard let id = try readActiveAccountID() else { return nil }
        return try loadIndex().first { $0.id == id }
    }

    public func addAccount(_ account: InstanceAccount, token: String) throws {
        var accounts = try loadIndex()
        guard !accounts.contains(where: { $0.id == account.id }) else { throw ConnectionIdentityError.sessionChanged }
        guard let userID = account.userID, userID > 0 else { throw ConnectionIdentityError.unverifiedUser }
        accounts.append(account)
        try persistSession(accounts, accountID: account.id, token: token)
        try writeActiveAccountID(account.id)
    }

    public func updateAccount(_ account: InstanceAccount, token: String?) throws {
        var accounts = try loadIndex()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw VikunjaError.notFound
        }
        let current = accounts[index]
        try current.validateIdentity(of: account)
        guard token == nil, current.userID == account.userID,
              current.authMethod == account.authMethod,
              current.needsReauthentication == account.needsReauthentication else {
            throw ConnectionIdentityError.sessionChanged
        }
        // This public metadata path only renames; it cannot rotate credentials or bind identity.
        accounts[index].displayName = account.displayName
        try saveIndex(accounts)
    }

    public func replaceSession(
        _ account: InstanceAccount, token: String, expected: InstanceAccount, matchingToken: String?,
    ) throws {
        try Task.checkCancellation()
        var accounts = try loadIndex()
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }),
              accounts[index] == expected,
              try self.token(forAccountID: expected.id) == matchingToken else {
            throw ConnectionIdentityError.sessionChanged
        }
        try expected.validateIdentity(of: account)
        guard let userID = account.userID, userID > 0 else { throw ConnectionIdentityError.unverifiedUser }
        accounts[index] = account
        try persistSession(accounts, accountID: account.id, token: token)
    }

    /// The actor keeps readers out until both writes finish; restore the prior secret on failure.
    private func persistSession(_ accounts: [InstanceAccount], accountID: UUID, token: String?) throws {
        let previous = try read(account: tokenItem(for: accountID))
        if let token {
            try save(Data(token.utf8), account: tokenItem(for: accountID))
        }
        do {
            try saveIndex(accounts)
        } catch {
            if let previous {
                try save(previous, account: tokenItem(for: accountID))
            } else {
                try delete(account: tokenItem(for: accountID))
            }
            throw error
        }
    }

    public func updateSession(
        for account: InstanceAccount,
        matchingToken: String,
        token: String?,
        needsReauthentication: Bool,
    ) throws -> Bool {
        guard try loadIndex().first(where: { $0.id == account.id }) == account,
              try self.token(forAccountID: account.id) == matchingToken else { return false }
        var updated = account
        updated.needsReauthentication = needsReauthentication
        var accounts = try loadIndex()
        guard let index = accounts.firstIndex(where: { $0 == account }) else { return false }
        accounts[index] = updated
        try persistSession(accounts, accountID: account.id, token: token)
        return true
    }

    public func removeAccount(id: InstanceAccount.ID) throws {
        var accounts = try loadIndex()
        accounts.removeAll { $0.id == id }
        try saveIndex(accounts)
        try delete(account: tokenItem(for: id))

        if try readActiveAccountID() == id {
            try delete(account: activeAccountItem)
            if let next = accounts.first {
                try writeActiveAccountID(next.id)
            }
        }
    }

    public func setActiveAccount(id: InstanceAccount.ID) throws {
        guard try loadIndex().contains(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        try writeActiveAccountID(id)
    }

    public func token(forAccountID id: InstanceAccount.ID) throws -> String? {
        guard let data = try read(account: tokenItem(for: id)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// One-time move of items written before `accessGroup` was configured
    /// (the app's private default group) into the shared group, so an
    /// existing install keeps working without the user re-adding the account.
    /// A no-op when the shared group is `nil` or unusable, or when it already
    /// has an index. Safe to call on every launch.
    public func migrateToAccessGroup() throws {
        guard let group = activeAccessGroup() else { return }
        if try Keychain.read(service: service, account: indexAccount, accessGroup: group) != nil {
            return
        }
        guard let legacyIndexData = try Keychain.read(service: service, account: indexAccount, accessGroup: nil) else {
            return
        }

        let accounts = try decoder.decode([InstanceAccount].self, from: legacyIndexData)
        try Keychain.save(legacyIndexData, service: service, account: indexAccount, accessGroup: group)

        if let activeData = try Keychain.read(service: service, account: activeAccountItem, accessGroup: nil) {
            try Keychain.save(activeData, service: service, account: activeAccountItem, accessGroup: group)
        }
        for account in accounts {
            let item = tokenItem(for: account.id)
            if let tokenData = try Keychain.read(service: service, account: item, accessGroup: nil) {
                try Keychain.save(tokenData, service: service, account: item, accessGroup: group)
            }
        }
    }

    // MARK: - Private

    /// Outer `nil` = not resolved yet; inner `nil` = resolved to "no group".
    private var resolvedAccessGroup: String??

    /// The access group actually used for every query. Resolved once, lazily:
    /// if the requested group can't be written to (the app was built without
    /// the matching `keychain-access-groups` entitlement, or the simulator
    /// doesn't honor it), fall back to the app's private keychain rather than
    /// failing every call — the widget won't see data until provisioning is
    /// fixed, but the app keeps working.
    private func activeAccessGroup() -> String? {
        if let resolved = resolvedAccessGroup {
            return resolved
        }

        guard let requested = accessGroup else {
            resolvedAccessGroup = .some(nil)
            return nil
        }

        let probe = "access-group-probe"
        do {
            try Keychain.save(Data("probe".utf8), service: service, account: probe, accessGroup: requested)
            _ = try Keychain.read(service: service, account: probe, accessGroup: requested)
            try Keychain.delete(service: service, account: probe, accessGroup: requested)
            resolvedAccessGroup = .some(requested)
            return requested
        } catch {
            resolvedAccessGroup = .some(nil)
            return nil
        }
    }

    private func tokenItem(for id: InstanceAccount.ID) -> String {
        "instance-token-\(id.uuidString)"
    }

    private func save(_ data: Data, account: String) throws {
        try Keychain.save(data, service: service, account: account, accessGroup: activeAccessGroup())
    }

    private func read(account: String) throws -> Data? {
        try Keychain.read(service: service, account: account, accessGroup: activeAccessGroup())
    }

    private func delete(account: String) throws {
        try Keychain.delete(service: service, account: account, accessGroup: activeAccessGroup())
    }

    /// A stored index that can't be decoded (corrupted, or written by an
    /// incompatible earlier build of the app) is treated as "no accounts"
    /// rather than left to fail every future account operation — the
    /// unreadable item is dropped so the next save starts clean.
    private func loadIndex() throws -> [InstanceAccount] {
        guard let data = try read(account: indexAccount) else { return [] }
        do {
            return try decoder.decode([InstanceAccount].self, from: data)
        } catch {
            try? delete(account: indexAccount)
            return []
        }
    }

    private func saveIndex(_ accounts: [InstanceAccount]) throws {
        try save(encoder.encode(accounts), account: indexAccount)
    }

    private func readActiveAccountID() throws -> UUID? {
        guard let data = try read(account: activeAccountItem),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return UUID(uuidString: string)
    }

    private func writeActiveAccountID(_ id: UUID) throws {
        try save(Data(id.uuidString.utf8), account: activeAccountItem)
    }
}
