#if DEBUG
import Foundation
import VikunjaCore

/// Credentials remain in memory and never reach the real Keychain.
actor UITestAccountStore: AccountStoreProtocol {
    private var accounts: [InstanceAccount] = [UITestAccountStore.fixtureAccount()]

    private static func fixtureAccount() -> InstanceAccount {
        guard let url = URL(string: "https://ui-testing.invalid") else {
            fatalError("Invalid UI testing instance URL")
        }
        return InstanceAccount(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            displayName: "UI Test Account",
            baseURL: url,
            createdAt: Date(timeIntervalSince1970: 0),
        )
    }

    private var activeID: UUID?
    private var credential = "ui-test-token"

    func fetchAccounts() async throws -> [InstanceAccount] {
        accounts
    }

    func activeAccount() async throws -> InstanceAccount? {
        if let activeID {
            return accounts.first { $0.id == activeID }
        }
        return accounts.first
    }

    func addAccount(_ account: InstanceAccount, token: String) async throws {
        throw UITestFixtureError.unsupported("Adding accounts")
    }

    func updateAccount(_ account: InstanceAccount, token: String?) async throws {
        throw UITestFixtureError.unsupported("Editing accounts")
    }

    func updateSession(
        for account: InstanceAccount, matchingToken: String, token: String?, needsReauthentication: Bool,
    ) async throws -> Bool {
        guard let index = accounts.firstIndex(of: account), matchingToken == credential else { return false }
        accounts[index].needsReauthentication = needsReauthentication
        if let token {
            credential = token
        }
        return true
    }

    func removeAccount(id: UUID) async throws {
        accounts.removeAll { $0.id == id }
    }

    func setActiveAccount(id: UUID) async throws {
        guard accounts.contains(where: { $0.id == id }) else { throw VikunjaError.notFound }
        activeID = id
    }

    func token(forAccountID id: UUID) async throws -> String? {
        accounts.contains(where: { $0.id == id }) ? credential : nil
    }
}
#endif
