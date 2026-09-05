import Foundation
@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct ConnectionFormViewModelTests {
    private func makeAccount(displayName: String = "Home", url: String = "https://tasks.example.com") -> InstanceAccount {
        InstanceAccount(displayName: displayName, baseURL: URL(string: url) ?? URL(filePath: "/"))
    }

    private func makeViewModel(
        mode: ConnectionFormMode,
        store: FakeAccountStore = FakeAccountStore(),
        factory: FakeInstanceClientFactory = FakeInstanceClientFactory(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
        oidcAuthenticator: FakeOIDCAuthenticating = FakeOIDCAuthenticating(),
        onActiveAccountChanged: @escaping () -> Void = {},
    ) -> ConnectionFormViewModel {
        ConnectionFormViewModel(
            mode: mode,
            accountStore: store,
            clientFactory: factory,
            toastPresenter: toastPresenter,
            oidcAuthenticator: oidcAuthenticator,
            oidcRedirectURI: URL(string: "viku://oidc-callback")!,
            onActiveAccountChanged: onActiveAccountChanged,
        )
    }

    // MARK: - create mode

    @Test
    func `create mode starts with blank fields and cannot save`() {
        let viewModel = makeViewModel(mode: .create)

        #expect(viewModel.displayName.isEmpty)
        #expect(viewModel.urlText.isEmpty)
        #expect(viewModel.apiToken.isEmpty)
        #expect(viewModel.canSave == false)
        #expect(viewModel.isEditing == false)
    }

    @Test
    func `saving in create mode probes and persists A new account and notifies`() async throws {
        let store = FakeAccountStore()
        var notifiedCount = 0
        let toastPresenter = FakeToastPresenter()
        let viewModel = makeViewModel(
            mode: .create,
            store: store,
            toastPresenter: toastPresenter,
            onActiveAccountChanged: { notifiedCount += 1 },
        )
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "secret"

        await viewModel.save()

        #expect(viewModel.validationState == .success)
        #expect(viewModel.savedAccount?.displayName == "Home")
        #expect(try await store.fetchAccounts().count == 1)
        #expect(try await store.activeAccount()?.displayName == "Home")
        #expect(notifiedCount == 1)
        #expect(toastPresenter.shownMessages.map(\.message) == ["Connection added"])
    }

    @Test
    func `saving in create mode surfaces A friendly message when the probe fails`() async {
        let factory = FakeInstanceClientFactory()
        factory.result = .failure(.network("offline"))
        let viewModel = makeViewModel(mode: .create, factory: factory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "secret"

        await viewModel.save()

        #expect(
            viewModel.validationState == .failure("Couldn't reach that server. Check the address and your connection."),
        )
        #expect(viewModel.savedAccount == nil)
    }

    // MARK: - edit mode

    @Test
    func `edit mode prefills name and URL from the existing account`() {
        let account = makeAccount(displayName: "Home", url: "https://tasks.example.com")
        let viewModel = makeViewModel(mode: .edit(account))

        #expect(viewModel.displayName == "Home")
        #expect(viewModel.urlText == "https://tasks.example.com")
        #expect(viewModel.isEditing == true)
    }

    @Test
    func `load prefills the existing token in edit mode`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "existing-token")
        let viewModel = makeViewModel(mode: .edit(account), store: store)

        await viewModel.load()

        #expect(viewModel.apiToken == "existing-token")
    }

    @Test
    func `saving in edit mode updates the account without changing the active pointer`() async throws {
        let store = FakeAccountStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        // `second` is active; edit `first`, the inactive one.
        var notifiedCount = 0
        let viewModel = makeViewModel(mode: .edit(first), store: store, onActiveAccountChanged: { notifiedCount += 1 })
        await viewModel.load()
        viewModel.displayName = "Renamed"

        await viewModel.save()

        #expect(viewModel.validationState == .success)
        #expect(try await store.fetchAccounts().first { $0.id == first.id }?.displayName == "Renamed")
        #expect(try await store.activeAccount() == second)
        // The active account's identity/shape didn't change, but the callback
        // still fires uniformly on every successful save — see the view
        // model's doc comment.
        #expect(notifiedCount == 1)
    }

    @Test
    func `saving in edit mode rotates the token when changed`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "old-token")
        let viewModel = makeViewModel(mode: .edit(account), store: store)
        await viewModel.load()
        viewModel.apiToken = "new-token"

        await viewModel.save()

        #expect(try await store.token(forAccountID: account.id) == "new-token")
    }

    @Test
    func `delete connection removes the account when another one exists`() async throws {
        let store = FakeAccountStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        let viewModel = makeViewModel(mode: .edit(first), store: store)

        let didDelete = await viewModel.deleteConnection()

        #expect(didDelete == true)
        #expect(try await store.fetchAccounts().map(\.id) == [second.id])
    }

    @Test
    func `delete connection refuses to remove the last account`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "token")
        let toastPresenter = FakeToastPresenter()
        let viewModel = makeViewModel(mode: .edit(account), store: store, toastPresenter: toastPresenter)

        let didDelete = await viewModel.deleteConnection()

        #expect(didDelete == false)
        #expect(try await store.fetchAccounts() == [account])
        #expect(toastPresenter.shownMessages.map(\.message) == ["You need at least one connection"])
    }

    @Test
    func `delete connection notifies only when the deleted account was active`() async throws {
        let store = FakeAccountStore()
        let first = makeAccount(displayName: "Home")
        let second = makeAccount(displayName: "Work")
        try await store.addAccount(first, token: "first-token")
        try await store.addAccount(second, token: "second-token")
        // `second` is active.
        var notifiedCount = 0
        let viewModel = makeViewModel(mode: .edit(second), store: store, onActiveAccountChanged: { notifiedCount += 1 })

        _ = await viewModel.deleteConnection()

        #expect(notifiedCount == 1)
    }

    @Test
    func `delete connection is A no op in create mode`() async {
        let viewModel = makeViewModel(mode: .create)

        let didDelete = await viewModel.deleteConnection()

        #expect(didDelete == false)
    }

    // MARK: - password login

    @Test
    func `checking local auth availability enables the password option without touching validation state`() async {
        let factory = FakeInstanceClientFactory()
        factory.supportsLocalAuth = true
        let viewModel = makeViewModel(mode: .create, factory: factory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.checkLocalAuthAvailability()

        #expect(viewModel.localAuthAvailable == true)
        #expect(viewModel.validationState == .idle)
    }

    @Test
    func `ing connection reverts away from password mode once local auth becomes unavailable`() async {
        let factory = FakeInstanceClientFactory()
        factory.supportsLocalAuth = false
        let viewModel = makeViewModel(mode: .create, factory: factory)
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password

        await viewModel.testConnection()

        #expect(viewModel.credentialMode == .apiToken)
    }

    @Test
    func `saving in create mode with password credentials logs in and persists`() async throws {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: "sergio"))
        factory.authService.loginResult = .success(session)
        let viewModel = makeViewModel(mode: .create, store: store, factory: factory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "hunter2"

        await viewModel.save()

        #expect(viewModel.validationState == .success)
        let accounts = try await store.fetchAccounts()
        #expect(accounts.first?.authMethod == .password)
        #expect(try await store.token(forAccountID: #require(accounts.first?.id)) == "opaque-blob")
    }

    @Test
    func `saving with password credentials and A totpRequired response awaits A code`() async {
        let factory = FakeInstanceClientFactory()
        factory.authService.loginResult = .failure(.totpRequired)
        let viewModel = makeViewModel(mode: .create, factory: factory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "hunter2"

        await viewModel.save()

        #expect(viewModel.awaitingTOTP == true)
        #expect(viewModel.validationState == .idle)
        #expect(viewModel.savedAccount == nil)
    }

    @Test
    func `editing an api token account to password credentials logs in and switches auth method`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "old-token")
        let factory = FakeInstanceClientFactory()
        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: "sergio"))
        factory.authService.loginResult = .success(session)
        let viewModel = makeViewModel(mode: .edit(account), store: store, factory: factory)
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "hunter2"

        await viewModel.save()

        #expect(viewModel.validationState == .success)
        let updated = try await store.fetchAccounts().first { $0.id == account.id }
        #expect(updated?.authMethod == .password)
        #expect(try await store.token(forAccountID: account.id) == "opaque-blob")
    }

    // MARK: - oidc login

    private static let oidcProvider = OIDCProvider(
        key: "authentik",
        name: "Authentik",
        authURL: URL(string: "https://auth.example.com/o/authorize/")!,
        clientID: "vikunja-client-id",
        scope: "openid email profile",
    )

    @Test
    func `checking local auth availability also populates oidc providers`() async {
        let factory = FakeInstanceClientFactory()
        factory.result = .success(
            VikunjaServerInfo(
                version: "0.24.6",
                caldavEnabled: false,
                totpEnabled: false,
                registrationEnabled: false,
                oidcProviders: [Self.oidcProvider],
            ),
        )
        let viewModel = makeViewModel(mode: .create, factory: factory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.checkLocalAuthAvailability()

        #expect(viewModel.oidcProviders == [Self.oidcProvider])
    }

    @Test
    func `signing in with oidc in create mode authenticates then persists an oidc account`() async throws {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let oidcAuthenticator = FakeOIDCAuthenticating()
        oidcAuthenticator.result = .success("auth-code")
        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: ""))
        factory.authService.loginResult = .success(session)
        let viewModel = makeViewModel(
            mode: .create,
            store: store,
            factory: factory,
            oidcAuthenticator: oidcAuthenticator,
        )
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(viewModel.validationState == .success)
        let accounts = try await store.fetchAccounts()
        #expect(accounts.first?.authMethod == .oidc)
        #expect(try await store.token(forAccountID: #require(accounts.first?.id)) == "opaque-blob")
    }

    @Test
    func `signing in with oidc in edit mode switches the existing account's auth method`() async throws {
        let store = FakeAccountStore()
        let account = makeAccount()
        try await store.addAccount(account, token: "old-token")
        let factory = FakeInstanceClientFactory()
        let oidcAuthenticator = FakeOIDCAuthenticating()
        oidcAuthenticator.result = .success("auth-code")
        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: ""))
        factory.authService.loginResult = .success(session)
        let viewModel = makeViewModel(
            mode: .edit(account),
            store: store,
            factory: factory,
            oidcAuthenticator: oidcAuthenticator,
        )

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(viewModel.validationState == .success)
        let updated = try await store.fetchAccounts().first { $0.id == account.id }
        #expect(updated?.authMethod == .oidc)
        #expect(try await store.token(forAccountID: account.id) == "opaque-blob")
    }

    @Test
    func `signing in with oidc surfaces an authentication failure`() async {
        let factory = FakeInstanceClientFactory()
        let oidcAuthenticator = FakeOIDCAuthenticating()
        oidcAuthenticator.result = .failure(.unauthorized)
        let viewModel = makeViewModel(mode: .create, factory: factory, oidcAuthenticator: oidcAuthenticator)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(viewModel.validationState == .failure("That server rejected the request."))
        #expect(viewModel.savedAccount == nil)
    }
}
