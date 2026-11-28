#if DEBUG
import Foundation
import VikunjaCore

/// Stores fixture credentials in the isolated run directory.
actor UITestAccountStore: AccountStoreProtocol {
    private nonisolated struct State: Codable, Sendable {
        var accounts: [InstanceAccount]
        var activeID: UUID?
        var credentials: [UUID: String]

        init(scenario: UITestScenario) {
            self.accounts = scenario == .unauthenticated ? [] : scenario.instances
            self.credentials = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, "ui-test-token-\($0.id)") })
        }
    }

    private let file: UITestStateFile<State>
    private var state: State

    init(directory: URL, seed: UITestScenario?) throws {
        let file = UITestStateFile<State>(url: directory.appendingPathComponent("accounts.json"))
        self.state = try file.load(seed: seed.map(State.init))
        self.file = file
    }

    func fetchAccounts() async throws -> [InstanceAccount] {
        state.accounts
    }

    func activeAccount() async throws -> InstanceAccount? {
        state.accounts.first { $0.id == state.activeID } ?? state.accounts.first
    }

    func addAccount(_ account: InstanceAccount, token: String) async throws {
        throw UITestFixtureError.unsupported("Adding accounts")
    }

    func updateAccount(_ account: InstanceAccount, token: String?) async throws {
        guard let index = state.accounts.firstIndex(where: { $0.id == account.id }) else {
            throw VikunjaError.notFound
        }
        try state.accounts[index].validateIdentity(of: account)
        guard token == nil else { throw ConnectionIdentityError.sessionChanged }
        try file.update(&state) { $0.accounts[index].displayName = account.displayName }
    }

    func replaceSession(
        _ account: InstanceAccount, token: String, expected: InstanceAccount, matchingToken: String?,
    ) async throws {
        guard let index = state.accounts.firstIndex(of: expected), state.credentials[account.id] == matchingToken else {
            throw ConnectionIdentityError.sessionChanged
        }
        try expected.validateIdentity(of: account)
        try file.update(&state) {
            $0.accounts[index] = account
            $0.credentials[account.id] = token
        }
    }

    func updateSession(
        for account: InstanceAccount, matchingToken: String, token: String?, needsReauthentication: Bool,
    ) async throws -> Bool {
        guard let index = state.accounts.firstIndex(of: account), state.credentials[account.id] == matchingToken else {
            return false
        }
        try file.update(&state) {
            $0.accounts[index].needsReauthentication = needsReauthentication
            if let token {
                $0.credentials[account.id] = token
            }
        }
        return true
    }

    func removeAccount(id: UUID) async throws {
        try file.update(&state) {
            $0.accounts.removeAll { $0.id == id }
            $0.credentials[id] = nil
            if $0.activeID == id {
                $0.activeID = nil
            }
        }
    }

    func setActiveAccount(id: UUID) async throws {
        guard state.accounts.contains(where: { $0.id == id }) else { throw VikunjaError.notFound }
        try file.update(&state) { $0.activeID = id }
    }

    func token(forAccountID id: UUID) async throws -> String? {
        state.credentials[id]
    }
}
#endif
