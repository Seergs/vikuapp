import Foundation
@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct ConnectionsListViewModelTests {
    private func makeAccount(displayName: String = "Home") -> InstanceAccount {
        InstanceAccount(displayName: displayName, baseURL: URL(string: "https://tasks.example.com")!)
    }

    private func makeViewModel(
        store: FakeAccountStore,
        clientFactory: FakeInstanceClientFactory = FakeInstanceClientFactory(),
        serverVersionCache: FakeServerVersionCaching = FakeServerVersionCaching(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
        onActiveAccountChanged: @escaping () -> Void = {},
    ) -> ConnectionsListViewModel {
        ConnectionsListViewModel(
            accountStore: store,
            clientFactory: clientFactory,
            serverVersionCache: serverVersionCache,
            toastPresenter: toastPresenter,
            onActiveAccountChanged: onActiveAccountChanged,
        )
    }

    @Test
    func `load populates accounts and the active ID`() async throws {
        let store = FakeAccountStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(Set(viewModel.accounts.map(\.id)) == Set([first.id, second.id]))
        #expect(viewModel.activeAccountID == second.id)
    }

    @Test
    func `load surfaces A friendly message on failure`() async {
        let store = FakeAccountStore()
        store.fetchAccountsError = .network("offline")
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
    }

    @Test
    func `load populates each account's server version`() async throws {
        let store = FakeAccountStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        let clientFactory = FakeInstanceClientFactory()
        let viewModel = makeViewModel(store: store, clientFactory: clientFactory)

        await viewModel.load()

        #expect(viewModel.serverVersions[first.id] == "0.24.6")
        #expect(viewModel.serverVersions[second.id] == "0.24.6")
    }

    @Test
    func `a failed version probe leaves that account without an entry`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "token")
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.result = .failure(.network("offline"))
        let viewModel = makeViewModel(store: store, clientFactory: clientFactory)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.serverVersions[account.id] == nil)
    }

    @Test
    func `load seeds server versions from the cache`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "token")
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.result = .failure(.network("offline"))
        let serverVersionCache = FakeServerVersionCaching(cached: [account.id: "0.22.1"])
        let viewModel = makeViewModel(
            store: store,
            clientFactory: clientFactory,
            serverVersionCache: serverVersionCache,
        )

        await viewModel.load()

        #expect(viewModel.serverVersions[account.id] == "0.22.1")
    }

    @Test
    func `a successful probe writes the fresh version through to the cache`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "token")
        let clientFactory = FakeInstanceClientFactory()
        let serverVersionCache = FakeServerVersionCaching(cached: [account.id: "0.22.1"])
        let viewModel = makeViewModel(
            store: store,
            clientFactory: clientFactory,
            serverVersionCache: serverVersionCache,
        )

        await viewModel.load()

        #expect(viewModel.serverVersions[account.id] == "0.24.6")
        #expect(serverVersionCache.cached[account.id] == "0.24.6")
    }

    @Test
    func `set active switches the active account and notifies`() async throws {
        let store = FakeAccountStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        var notifiedCount = 0
        let viewModel = makeViewModel(store: store, onActiveAccountChanged: { notifiedCount += 1 })
        await viewModel.load()

        await viewModel.setActive(first)

        #expect(viewModel.activeAccountID == first.id)
        #expect(try await store.activeAccount() == first)
        #expect(notifiedCount == 1)
    }

    @Test
    func `set active on the already active account does nothing`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "token")
        var notifiedCount = 0
        let viewModel = makeViewModel(store: store, onActiveAccountChanged: { notifiedCount += 1 })
        await viewModel.load()

        await viewModel.setActive(account)

        #expect(notifiedCount == 0)
    }
}
