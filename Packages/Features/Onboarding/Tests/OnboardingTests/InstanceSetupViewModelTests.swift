import Foundation
@testable import Onboarding
import Testing
import VikunjaCore

@MainActor
struct InstanceSetupViewModelTests {
    private func makeViewModel(
        accountStore: FakeAccountStore = FakeAccountStore(),
        clientFactory: FakeInstanceClientFactory = FakeInstanceClientFactory(),
        oidcAuthenticator: FakeOIDCAuthenticating = FakeOIDCAuthenticating(),
    ) -> InstanceSetupViewModel {
        InstanceSetupViewModel(
            accountStore: accountStore,
            clientFactory: clientFactory,
            oidcAuthenticator: oidcAuthenticator,
            oidcRedirectURI: URL(string: "viku://oidc-callback")!,
        )
    }

    @Test
    func `can save is false until all fields are filled`() {
        let viewModel = makeViewModel()
        #expect(viewModel.canSave == false)

        viewModel.displayName = "Home"
        #expect(viewModel.canSave == false)

        viewModel.urlText = "tasks.example.com"
        #expect(viewModel.canSave == false)

        viewModel.apiToken = "a-token"
        #expect(viewModel.canSave == true)
    }

    @Test
    func `can save is false when fields are only whitespace`() {
        let viewModel = makeViewModel()
        viewModel.displayName = "   "
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "a-token"

        #expect(viewModel.canSave == false)
    }

    @Test
    func `saving A valid connection probes the normalized URL and persists the account`() async throws {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        let viewModel = makeViewModel(accountStore: accountStore, clientFactory: clientFactory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "a-token"

        await viewModel.saveConnection()

        #expect(viewModel.validationState == .success)
        #expect(try clientFactory.requestedBaseURLs == [#require(URL(string: "https://tasks.example.com"))])
        #expect(accountStore.accounts.count == 1)
        #expect(accountStore.accounts.first?.displayName == "Home")
        #expect(accountStore.accounts.first?.baseURL == URL(string: "https://tasks.example.com")!)
        #expect(try accountStore.tokens[#require(accountStore.accounts.first?.id)] == "a-token")
    }

    @Test
    func `saving A valid connection exposes the saved account`() async {
        let viewModel = makeViewModel()
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "a-token"
        #expect(viewModel.savedAccount == nil)

        await viewModel.saveConnection()

        #expect(viewModel.savedAccount?.displayName == "Home")
    }

    @Test
    func `ing successfully does not expose A saved account`() async {
        let viewModel = makeViewModel()
        viewModel.urlText = "tasks.example.com"

        await viewModel.testConnection()

        #expect(viewModel.validationState == .success)
        #expect(viewModel.savedAccount == nil)
    }

    @Test
    func `saving clears the input fields on success`() async {
        let viewModel = makeViewModel()
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "a-token"

        await viewModel.saveConnection()

        #expect(viewModel.displayName.isEmpty)
        #expect(viewModel.urlText.isEmpty)
        #expect(viewModel.apiToken.isEmpty)
    }

    @Test
    func `saving reloads the account list`() async {
        let viewModel = makeViewModel()
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "a-token"

        await viewModel.saveConnection()

        #expect(viewModel.savedAccounts.count == 1)
        #expect(viewModel.savedAccounts.first?.displayName == "Home")
    }

    @Test
    func `saving an invalid URL fails without touching the account store`() async {
        let accountStore = FakeAccountStore()
        let viewModel = makeViewModel(accountStore: accountStore)
        viewModel.displayName = "Home"
        viewModel.urlText = "not a url"
        viewModel.apiToken = "a-token"

        await viewModel.saveConnection()

        #expect(viewModel.validationState == .failure("That doesn't look like a valid instance address."))
        #expect(accountStore.addAccountCallCount == 0)
    }

    @Test
    func `saving when the server probe fails surfaces A friendly message and does not persist`() async {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.result = .failure(.network("offline"))
        let viewModel = makeViewModel(accountStore: accountStore, clientFactory: clientFactory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.apiToken = "a-token"

        await viewModel.saveConnection()

        #expect(
            viewModel.validationState == .failure("Couldn't reach that server. Check the address and your connection."),
        )
        #expect(accountStore.addAccountCallCount == 0)
    }

    @Test
    func `saving when not all fields are filled does nothing`() async {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        let viewModel = makeViewModel(accountStore: accountStore, clientFactory: clientFactory)
        viewModel.displayName = "Home"

        await viewModel.saveConnection()

        #expect(viewModel.validationState == .idle)
        #expect(accountStore.addAccountCallCount == 0)
        #expect(clientFactory.requestedBaseURLs.isEmpty)
    }

    @Test
    func `can test connection is false until an address is typed`() {
        let viewModel = makeViewModel()
        #expect(viewModel.canTestConnection == false)

        viewModel.urlText = "   "
        #expect(viewModel.canTestConnection == false)

        viewModel.urlText = "tasks.example.com"
        #expect(viewModel.canTestConnection == true)
    }

    @Test
    func `ing A valid address probes it without persisting an account`() async throws {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        let viewModel = makeViewModel(accountStore: accountStore, clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.testConnection()

        #expect(viewModel.validationState == .success)
        #expect(try clientFactory.requestedBaseURLs == [#require(URL(string: "https://tasks.example.com"))])
        #expect(accountStore.addAccountCallCount == 0)
        #expect(viewModel.urlText == "tasks.example.com")
    }

    @Test
    func `ing when the server probe fails surfaces A friendly message`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.result = .failure(.network("offline"))
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.testConnection()

        #expect(
            viewModel.validationState == .failure("Couldn't reach that server. Check the address and your connection."),
        )
    }

    @Test
    func `ing with no address does nothing`() async {
        let clientFactory = FakeInstanceClientFactory()
        let viewModel = makeViewModel(clientFactory: clientFactory)

        await viewModel.testConnection()

        #expect(viewModel.validationState == .idle)
        #expect(clientFactory.requestedBaseURLs.isEmpty)
    }

    @Test
    func `load saved accounts populates from the store`() async throws {
        let accountStore = FakeAccountStore()
        let existing = try InstanceAccount(displayName: "Work", baseURL: #require(URL(string: "https://work.example.com")))
        try? await accountStore.addAccount(existing, token: "work-token")
        let viewModel = makeViewModel(accountStore: accountStore)

        await viewModel.loadSavedAccounts()

        #expect(viewModel.savedAccounts == [existing])
    }

    @Test
    func `ing connection reports whether local auth is available`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.supportsLocalAuth = true
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.testConnection()

        #expect(viewModel.localAuthAvailable == true)
    }

    @Test
    func `checking local auth availability enables the password option without touching validation state`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.supportsLocalAuth = true
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.checkLocalAuthAvailability()

        #expect(viewModel.localAuthAvailable == true)
        #expect(viewModel.validationState == .idle)
    }

    @Test
    func `ing connection reverts away from password mode once local auth becomes unavailable`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.supportsLocalAuth = false
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password

        await viewModel.testConnection()

        #expect(viewModel.credentialMode == .apiToken)
    }

    @Test
    func `saving in password mode logs in and persists A password account`() async throws {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: "sergio"))
        clientFactory.authService.loginResult = .success(session)
        let viewModel = makeViewModel(accountStore: accountStore, clientFactory: clientFactory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "hunter2"

        await viewModel.saveConnection()

        #expect(viewModel.validationState == .success)
        #expect(accountStore.accounts.first?.authMethod == .password)
        #expect(try accountStore.tokens[#require(accountStore.accounts.first?.id)] == "opaque-blob")
        #expect(clientFactory.authService.loginCredentials.first?.username == "sergio")
    }

    @Test
    func `saving in password mode with A totpRequired response awaits A code instead of failing`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.authService.loginResult = .failure(.totpRequired)
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "hunter2"

        await viewModel.saveConnection()

        #expect(viewModel.awaitingTOTP == true)
        #expect(viewModel.validationState == .idle)
        #expect(viewModel.savedAccount == nil)
    }

    @Test
    func `saving in password mode retries with the totp code once awaiting one`() async {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.authService.loginResult = .failure(.totpRequired)
        let viewModel = makeViewModel(accountStore: accountStore, clientFactory: clientFactory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "hunter2"
        await viewModel.saveConnection()
        #expect(viewModel.awaitingTOTP == true)

        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: "sergio"))
        clientFactory.authService.loginResult = .success(session)
        viewModel.totpPasscode = "123456"
        await viewModel.saveConnection()

        #expect(viewModel.validationState == .success)
        #expect(accountStore.accounts.count == 1)
        #expect(clientFactory.authService.loginCredentials.last?.totpPasscode == "123456")
    }

    @Test
    func `saving in password mode surfaces A wrong password as A failure`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.authService.loginResult = .failure(.unauthorized)
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"
        viewModel.credentialMode = .password
        viewModel.username = "sergio"
        viewModel.password = "wrong"

        await viewModel.saveConnection()

        #expect(viewModel.validationState == .failure("That server rejected the request."))
        #expect(viewModel.savedAccount == nil)
    }

    private static let oidcProvider = OIDCProvider(
        key: "authentik",
        name: "Authentik",
        authURL: URL(string: "https://auth.example.com/o/authorize/")!,
        clientID: "vikunja-client-id",
        scope: "openid email profile",
    )

    @Test
    func `checking local auth availability also populates oidc providers`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.result = .success(
            VikunjaServerInfo(
                version: "0.24.6",
                caldavEnabled: false,
                totpEnabled: false,
                registrationEnabled: false,
                oidcProviders: [Self.oidcProvider],
            ),
        )
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"

        await viewModel.checkLocalAuthAvailability()

        #expect(viewModel.oidcProviders == [Self.oidcProvider])
    }

    @Test
    func `checking local auth availability clears the options once the address goes away`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.supportsLocalAuth = true
        clientFactory.result = .success(
            VikunjaServerInfo(
                version: "0.24.6",
                caldavEnabled: false,
                totpEnabled: false,
                registrationEnabled: false,
                oidcProviders: [Self.oidcProvider],
            ),
        )
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"
        await viewModel.checkLocalAuthAvailability()
        #expect(viewModel.localAuthAvailable == true)
        #expect(viewModel.oidcProviders == [Self.oidcProvider])

        viewModel.urlText = ""
        await viewModel.checkLocalAuthAvailability()

        #expect(viewModel.localAuthAvailable == false)
        #expect(viewModel.oidcProviders.isEmpty)
    }

    @Test
    func `checking local auth availability clears the options when the probe fails`() async {
        let clientFactory = FakeInstanceClientFactory()
        clientFactory.supportsLocalAuth = true
        clientFactory.result = .success(
            VikunjaServerInfo(
                version: "0.24.6",
                caldavEnabled: false,
                totpEnabled: false,
                registrationEnabled: false,
                oidcProviders: [Self.oidcProvider],
            ),
        )
        let viewModel = makeViewModel(clientFactory: clientFactory)
        viewModel.urlText = "tasks.example.com"
        await viewModel.checkLocalAuthAvailability()
        #expect(viewModel.oidcProviders == [Self.oidcProvider])

        clientFactory.result = .failure(.network("unreachable"))
        viewModel.urlText = "tasks.broken.example"
        await viewModel.checkLocalAuthAvailability()

        #expect(viewModel.localAuthAvailable == false)
        #expect(viewModel.oidcProviders.isEmpty)
    }

    @Test
    func `sign in with oidc authenticates then persists an oidc account`() async throws {
        let accountStore = FakeAccountStore()
        let clientFactory = FakeInstanceClientFactory()
        let oidcAuthenticator = FakeOIDCAuthenticating()
        oidcAuthenticator.result = .success("auth-code")
        let session = AuthSession(token: "opaque-blob", user: User(id: 1, username: ""))
        clientFactory.authService.loginResult = .success(session)
        let viewModel = makeViewModel(
            accountStore: accountStore,
            clientFactory: clientFactory,
            oidcAuthenticator: oidcAuthenticator,
        )
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(viewModel.validationState == .success)
        #expect(accountStore.accounts.first?.authMethod == .oidc)
        #expect(try accountStore.tokens[#require(accountStore.accounts.first?.id)] == "opaque-blob")
        #expect(oidcAuthenticator.requestedProviders == [Self.oidcProvider])
    }

    @Test
    func `sign in with oidc surfaces an authentication failure`() async {
        let clientFactory = FakeInstanceClientFactory()
        let oidcAuthenticator = FakeOIDCAuthenticating()
        oidcAuthenticator.result = .failure(VikunjaError.unauthorized)
        let viewModel = makeViewModel(clientFactory: clientFactory, oidcAuthenticator: oidcAuthenticator)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(viewModel.validationState == .failure("That server rejected the request."))
        #expect(viewModel.savedAccount == nil)
    }

    @Test
    func `sign in with oidc returns to idle without an error banner when canceled`() async {
        let oidcAuthenticator = FakeOIDCAuthenticating()
        oidcAuthenticator.result = .failure(OIDCAuthError.canceled)
        let viewModel = makeViewModel(oidcAuthenticator: oidcAuthenticator)
        viewModel.displayName = "Home"
        viewModel.urlText = "tasks.example.com"

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(viewModel.validationState == .idle)
        #expect(viewModel.savedAccount == nil)
    }

    @Test
    func `sign in with oidc does nothing when the name or address is missing`() async {
        let oidcAuthenticator = FakeOIDCAuthenticating()
        let viewModel = makeViewModel(oidcAuthenticator: oidcAuthenticator)

        await viewModel.signInWithOIDC(Self.oidcProvider)

        #expect(oidcAuthenticator.requestedProviders.isEmpty)
        #expect(viewModel.validationState == .idle)
    }
}
