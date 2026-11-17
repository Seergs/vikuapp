import Foundation
import Testing
@testable import VikuAuth
import VikunjaCore

/// Exercises the real Keychain (generic password items), so this suite runs
/// serialized against a service namespace unique to the test process to avoid
/// clobbering state across parallel test runs.
@Suite(.serialized)
struct KeychainAccountStoreTests {
    private func makeStore() -> KeychainAccountStore {
        KeychainAccountStore(service: "dev.sergiosuarez.viku.tests.\(UUID().uuidString)")
    }

    private func makeAccount(displayName: String = "Home") -> InstanceAccount {
        InstanceAccount(displayName: displayName, baseURL: URL(string: "https://tasks.example.com")!)
    }

    @Test
    func `renewal cannot overwrite a replacement credential or revive a removed account`() async throws {
        let store = makeStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "old")
        #expect(try await store.updateSession(
            for: account, matchingToken: "old", token: "renewed", needsReauthentication: false,
        ))
        try await store.updateAccount(account, token: "new-login")
        #expect(try await !store.updateSession(
            for: account, matchingToken: "renewed", token: "late-result", needsReauthentication: false,
        ))
        #expect(try await !store.updateSession(
            for: account, matchingToken: "renewed", token: nil, needsReauthentication: true,
        ))
        #expect(try await store.token(forAccountID: account.id) == "new-login")
        #expect(try await store.activeAccount()?.needsReauthentication == false)
        try await store.removeAccount(id: account.id)
        #expect(try await !store.updateSession(
            for: account, matchingToken: "new-login", token: "late-result", needsReauthentication: false,
        ))
        #expect(try await store.fetchAccounts().isEmpty)
    }

    @Test
    func `falls back to the private keychain when the access group is unusable`() async throws {
        // A bogus access group the test process has no entitlement for: the
        // store must not fail every call, it must transparently fall back to
        // the app's private keychain.
        let service = "dev.sergiosuarez.viku.tests.\(UUID().uuidString)"
        let store = KeychainAccountStore(service: service, accessGroup: "bogus.unentitled.group")
        let account = makeAccount()

        try await store.addAccount(account, token: "secret-token")

        #expect(try await store.activeAccount() == account)
        #expect(try await store.token(forAccountID: account.id) == "secret-token")

        // And a store without any group sees the same items.
        let plain = KeychainAccountStore(service: service)
        #expect(try await plain.fetchAccounts() == [account])
    }

    @Test
    func `an unreadable stored index self heals to no accounts instead of failing every call`() async throws {
        let service = "dev.sergiosuarez.viku.tests.\(UUID().uuidString)"
        // Simulates data written by an incompatible earlier build (or plain
        // corruption) — garbage where the account index JSON should be.
        try Keychain.save(Data("not valid json".utf8), service: service, account: "instance-accounts-index")
        let store = KeychainAccountStore(service: service)

        let accounts = try await store.fetchAccounts()

        #expect(accounts.isEmpty)

        // The unreadable item was dropped, so a fresh save works cleanly
        // afterward rather than the corruption blocking every future call.
        let account = makeAccount()
        try await store.addAccount(account, token: "secret-token")
        #expect(try await store.fetchAccounts() == [account])
    }

    @Test
    func `starts with no accounts`() async throws {
        let store = makeStore()

        #expect(try await store.fetchAccounts().isEmpty)
        #expect(try await store.activeAccount() == nil)
    }

    @Test
    func `adding an account persists it and its token and makes it active`() async throws {
        let store = makeStore()
        let account = makeAccount()

        try await store.addAccount(account, token: "secret-token")

        #expect(try await store.fetchAccounts() == [account])
        #expect(try await store.activeAccount() == account)
        #expect(try await store.token(forAccountID: account.id) == "secret-token")
    }

    @Test
    func `adding A second account makes it the active one without losing the first`() async throws {
        let store = makeStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")

        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")

        #expect(try await Set(store.fetchAccounts().map(\.id)) == Set([first.id, second.id]))
        #expect(try await store.activeAccount() == second)
        #expect(try await store.token(forAccountID: first.id) == "first-token")
    }

    @Test
    func `set active account switches the active pointer`() async throws {
        let store = makeStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")

        try await store.setActiveAccount(id: first.id)

        #expect(try await store.activeAccount() == first)
    }

    @Test
    func `set active account throws for an unknown ID`() async throws {
        let store = makeStore()

        await #expect(throws: VikunjaError.notFound) {
            try await store.setActiveAccount(id: UUID())
        }
    }

    @Test
    func `updating an account changes its metadata without touching the active pointer`() async throws {
        let store = makeStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        try await store.setActiveAccount(id: first.id)

        var renamed = second
        renamed.displayName = "Office"
        try await store.updateAccount(renamed, token: nil)

        #expect(try await store.fetchAccounts().contains(renamed))
        #expect(try await store.activeAccount() == first)
        #expect(try await store.token(forAccountID: second.id) == "second-token")
    }

    @Test
    func `updating an account with A token rotates the stored credential`() async throws {
        let store = makeStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "old-token")

        try await store.updateAccount(account, token: "new-token")

        #expect(try await store.token(forAccountID: account.id) == "new-token")
    }

    @Test
    func `updating an unknown account throws`() async throws {
        let store = makeStore()

        await #expect(throws: VikunjaError.notFound) {
            try await store.updateAccount(makeAccount(), token: nil)
        }
    }

    @Test
    func `removing the active account promotes another one`() async throws {
        let store = makeStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")

        try await store.removeAccount(id: second.id)

        #expect(try await store.fetchAccounts() == [first])
        #expect(try await store.activeAccount() == first)
        #expect(try await store.token(forAccountID: second.id) == nil)
    }

    @Test
    func `removing the last account leaves no active account`() async throws {
        let store = makeStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "secret-token")

        try await store.removeAccount(id: account.id)

        #expect(try await store.fetchAccounts().isEmpty)
        #expect(try await store.activeAccount() == nil)
    }
}
