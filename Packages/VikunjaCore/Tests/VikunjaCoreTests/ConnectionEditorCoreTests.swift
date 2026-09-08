import Foundation
import Testing
@testable import VikunjaCore

@MainActor
@Suite("ConnectionEditorCore")
struct ConnectionEditorCoreTests {
    private static let redirectURI = URL(string: "viku://oidc-callback")!

    private static let oidcProvider = OIDCProvider(
        key: "authentik",
        name: "Authentik",
        authURL: URL(string: "https://auth.example.com/o/authorize/")!,
        clientID: "vikunja-client-id",
        scope: "openid email profile",
    )

    private func makeCore(
        editingAccount: InstanceAccount? = nil,
        store: FakeAccountStore = FakeAccountStore(),
        factory: FakeInstanceClientFactory = FakeInstanceClientFactory(),
        oidcAuthenticator: FakeOIDCAuthenticating = FakeOIDCAuthenticating(),
    ) -> ConnectionEditorCore {
        ConnectionEditorCore(
            editingAccount: editingAccount,
            accountStore: store,
            clientFactory: factory,
            oidcAuthenticator: oidcAuthenticator,
            oidcRedirectURI: Self.redirectURI,
        )
    }

    // MARK: - validation

    @Test
    func `can save requires a name, an address and a token in api-token mode`() {
        let core = makeCore()
        #expect(core.canSave == false)

        core.displayName = "Home"
        core.urlText = "tasks.example.com"
        #expect(core.canSave == false)

        core.apiToken = "a-token"
        #expect(core.canSave == true)
    }

    @Test
    func `whitespace-only fields do not count`() {
        let core = makeCore()
        core.displayName = "   "
        core.urlText = "tasks.example.com"
        core.apiToken = "a-token"
        #expect(core.canSave == false)
    }

    @Test
    func `insecure scheme is only flagged for an explicit http address`() {
        let core = makeCore()
        core.urlText = "tasks.example.com"
        #expect(core.urlUsesInsecureScheme == false)
        core.urlText = "https://tasks.example.com"
        #expect(core.urlUsesInsecureScheme == false)
        core.urlText = "HTTP://localhost:3456"
        #expect(core.urlUsesInsecureScheme == true)
    }

    @Test
    func `editing account prefills the fields`() throws {
        let account = try InstanceAccount(
            displayName: "Local", baseURL: #require(URL(string: "http://localhost:3456")), authMethod: .password,
        )
        let core = makeCore(editingAccount: account)

        #expect(core.displayName == "Local")
        #expect(core.urlText == "http://localhost:3456")
        #expect(core.credentialMode == .password)
        #expect(core.allowInsecureConnection == true)
    }

    // MARK: - save (add)

    @Test
    func `saving in api-token mode probes the normalized URL and adds the account`() async throws {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let core = makeCore(store: store, factory: factory)
        var storedAccounts: [InstanceAccount] = []
        core.onStored = { storedAccounts.append($0) }
        core.displayName = "Home"
        core.urlText = "tasks.example.com"
        core.apiToken = "a-token"

        await core.save()

        #expect(core.phase == .success)
        #expect(try factory.requestedBaseURLs == [#require(URL(string: "https://tasks.example.com"))])
        #expect(store.accounts.first?.displayName == "Home")
        #expect(try #require(store.accounts.first).authMethod == .apiToken)
        #expect(storedAccounts.count == 1)
        #expect(core.savedAccount == storedAccounts.first)
    }

    @Test
    func `saving an http address is rejected unless insecure connections are allowed`() async {
        let store = FakeAccountStore()
        let core = makeCore(store: store)
        core.displayName = "Local"
        core.urlText = "http://localhost:3456"
        core.apiToken = "a-token"

        await core.save()

        #expect(core.phase == .failure(
            "That address uses http. Turn on \"Allow insecure connection\" to connect over an unencrypted link.",
        ))
        #expect(store.accounts.isEmpty)
    }

    @Test
    func `a failed probe surfaces a friendly message and persists nothing`() async {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        factory.result = .failure(.network("offline"))
        let core = makeCore(store: store, factory: factory)
        core.displayName = "Home"
        core.urlText = "tasks.example.com"
        core.apiToken = "a-token"

        await core.save()

        #expect(core.phase == .failure("Couldn't reach that server. Check the address and your connection."))
        #expect(store.accounts.isEmpty)
    }

    // MARK: - save (update)

    @Test
    func `saving while editing updates the same account in place`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(displayName: "Home", baseURL: #require(URL(string: "https://tasks.example.com")))
        try await store.addAccount(account, token: "old-token")
        let core = makeCore(editingAccount: account, store: store)
        core.displayName = "Renamed"
        core.apiToken = "new-token"

        await core.save()

        #expect(core.phase == .success)
        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == account.id)
        #expect(store.accounts.first?.displayName == "Renamed")
        #expect(store.tokens[account.id] == "new-token")
    }

    // MARK: - password

    @Test
    func `password login persists an opaque credential`() async throws {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        factory.authService.loginResult = .success(
            AuthSession(token: "opaque-blob", user: User(id: 1, username: "sergio")),
        )
        let core = makeCore(store: store, factory: factory)
        core.displayName = "Home"
        core.urlText = "tasks.example.com"
        core.credentialMode = .password
        core.username = "sergio"
        core.password = "hunter2"

        await core.save()

        #expect(core.phase == .success)
        #expect(store.accounts.first?.authMethod == .password)
        #expect(try store.tokens[#require(store.accounts.first).id] == "opaque-blob")
    }

    @Test
    func `a totpRequired response awaits a code rather than failing`() async {
        let factory = FakeInstanceClientFactory()
        factory.authService.loginResult = .failure(.totpRequired)
        let core = makeCore(factory: factory)
        core.displayName = "Home"
        core.urlText = "tasks.example.com"
        core.credentialMode = .password
        core.username = "sergio"
        core.password = "hunter2"

        await core.save()

        #expect(core.awaitingTOTP == true)
        #expect(core.phase == .idle)
        #expect(core.savedAccount == nil)
    }

    @Test
    func `probing reverts away from password mode when local auth is unavailable`() async {
        let factory = FakeInstanceClientFactory()
        factory.supportsLocalAuth = false
        let core = makeCore(factory: factory)
        core.urlText = "tasks.example.com"
        core.credentialMode = .password

        await core.testConnection()

        #expect(core.credentialMode == .apiToken)
    }

    // MARK: - OIDC

    @Test
    func `oidc sign-in authenticates then persists an oidc account`() async {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let oidc = FakeOIDCAuthenticating()
        oidc.result = .success("auth-code")
        factory.authService.loginResult = .success(AuthSession(token: "opaque-blob", user: User(id: 1, username: "")))
        let core = makeCore(store: store, factory: factory, oidcAuthenticator: oidc)
        core.displayName = "Home"
        core.urlText = "tasks.example.com"

        await core.signInWithOIDC(Self.oidcProvider)

        #expect(core.phase == .success)
        #expect(store.accounts.first?.authMethod == .oidc)
        #expect(oidc.requestedProviders == [Self.oidcProvider])
    }

    @Test
    func `a canceled oidc sign-in returns to idle with no error banner`() async {
        let oidc = FakeOIDCAuthenticating()
        oidc.result = .failure(OIDCAuthError.canceled)
        let core = makeCore(oidcAuthenticator: oidc)
        core.displayName = "Home"
        core.urlText = "tasks.example.com"

        await core.signInWithOIDC(Self.oidcProvider)

        #expect(core.phase == .idle)
        #expect(core.savedAccount == nil)
    }

    // MARK: - reset

    @Test
    func `resetInputs clears the form but leaves the save result readable`() async {
        let core = makeCore()
        core.displayName = "Home"
        core.urlText = "tasks.example.com"
        core.apiToken = "a-token"
        await core.save()

        core.resetInputs()

        #expect(core.displayName.isEmpty)
        #expect(core.urlText.isEmpty)
        #expect(core.apiToken.isEmpty)
        #expect(core.credentialMode == .apiToken)
        #expect(core.phase == .success)
        #expect(core.savedAccount != nil)
    }
}

// MARK: - Fakes

private final class FakeAccountStore: AccountStoreProtocol, @unchecked Sendable {
    private(set) var accounts: [InstanceAccount] = []
    private(set) var tokens: [InstanceAccount.ID: String] = [:]
    private var activeID: InstanceAccount.ID?

    func fetchAccounts() async throws -> [InstanceAccount] {
        accounts
    }

    func activeAccount() async throws -> InstanceAccount? {
        accounts.first { $0.id == activeID }
    }

    func addAccount(_ account: InstanceAccount, token: String) async throws {
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        tokens[account.id] = token
        activeID = account.id
    }

    func updateAccount(_ account: InstanceAccount, token: String?) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { throw VikunjaError.notFound }
        accounts[index] = account
        if let token {
            tokens[account.id] = token
        }
    }

    func removeAccount(id: InstanceAccount.ID) async throws {
        accounts.removeAll { $0.id == id }
        tokens[id] = nil
    }

    func setActiveAccount(id: InstanceAccount.ID) async throws {
        activeID = id
    }

    func token(forAccountID id: InstanceAccount.ID) async throws -> String? {
        tokens[id]
    }
}

private struct FakeCapabilityProvider: CapabilityProvider {
    var result: Result<VikunjaServerInfo, VikunjaError>
    var supportsLocalAuth: Bool

    func serverInfo() async throws -> VikunjaServerInfo {
        try result.get()
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        feature == .localAuth ? supportsLocalAuth : false
    }
}

private final class FakeAuthService: AuthServiceProtocol, @unchecked Sendable {
    var loginResult: Result<AuthSession, VikunjaError> = .failure(.network("not configured"))
    private(set) var loginCredentials: [LoginCredentials] = []

    func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        loginCredentials.append(credentials)
        return try loginResult.get()
    }

    func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        AuthSession(token: token, user: User(id: 0, username: ""))
    }

    func loginWithOIDC(provider _: OIDCProvider, code _: String, redirectURI _: URL) async throws -> AuthSession {
        try loginResult.get()
    }

    func logout() async {}
}

private final class FakeOIDCAuthenticating: OIDCAuthenticating, @unchecked Sendable {
    var result: Result<String, Error> = .failure(VikunjaError.network("not configured"))
    private(set) var requestedProviders: [OIDCProvider] = []

    func authenticate(provider: OIDCProvider, redirectURI _: URL) async throws -> String {
        requestedProviders.append(provider)
        return try result.get()
    }
}

private final class FakeInstanceClientFactory: InstanceClientFactoryProtocol, @unchecked Sendable {
    var result: Result<VikunjaServerInfo, VikunjaError> = .success(
        VikunjaServerInfo(version: "0.24.6", caldavEnabled: false, totpEnabled: false, registrationEnabled: false),
    )
    var supportsLocalAuth = true
    let authService = FakeAuthService()
    private(set) var requestedBaseURLs: [URL] = []

    func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider {
        requestedBaseURLs.append(baseURL)
        return FakeCapabilityProvider(result: result, supportsLocalAuth: supportsLocalAuth)
    }

    func makeAuthService(baseURL _: URL) -> AuthServiceProtocol {
        authService
    }

    func makeProjectRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> ProjectRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskRepositoryProtocol {
        fatalError("unused")
    }

    func makeLabelRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> LabelRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskRelationRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskCommentRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskAttachmentRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("unused")
    }

    func makeUserRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("unused")
    }
}
