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

        #expect(core.phase == .failure("That address uses an insecure http connection."))
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

    @Test
    func `saving while editing clears a stale needsReauthentication flag`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(
            displayName: "Home",
            baseURL: #require(URL(string: "https://tasks.example.com")),
            needsReauthentication: true,
        )
        try await store.addAccount(account, token: "old-token")
        let core = makeCore(editingAccount: account, store: store)
        core.apiToken = "new-token"

        await core.save()

        #expect(store.accounts.first?.needsReauthentication == false)
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

    @Test(arguments: [InstanceAccount.AuthMethod.apiToken, .password, .oidc])
    func `a different user cannot replace an existing connection`(method: InstanceAccount.AuthMethod) async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(
            displayName: "Home", baseURL: #require(URL(string: "https://tasks.example.com")), userID: 1, username: "sergio",
        )
        try await store.addAccount(account, token: "original")
        let factory = FakeInstanceClientFactory()
        factory.authService.apiTokenUser = User(id: 2, username: "other")
        factory.authService.loginResult = .success(
            AuthSession(token: "candidate", user: User(id: 2, username: "other")),
        )
        let browser = FakeOIDCAuthenticating()
        browser.result = .success("code")
        let core = makeCore(editingAccount: account, store: store, factory: factory, oidcAuthenticator: browser)
        core.credentialMode = method
        core.apiToken = "candidate"
        core.username = "other"
        core.password = "password"
        var notified = false
        core.onStored = { _ in notified = true }
        if method == .oidc {
            await core.signInWithOIDC(Self.oidcProvider)
        } else {
            await core.save()
        }
        #expect(core.phase == .failure(ConnectionIdentityError.userChanged.localizedDescription))
        #expect(store.accounts == [account])
        #expect(store.tokens[account.id] == "original")
        #expect(!notified)
    }

    @Test
    func `server changes are rejected before contacting another server`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(displayName: "Home", baseURL: #require(URL(string: "https://source.example.com")))
        try await store.addAccount(account, token: "original")
        let factory = FakeInstanceClientFactory()
        let core = makeCore(editingAccount: account, store: store, factory: factory)
        core.urlText = "https://target.example.com"
        core.apiToken = "candidate"
        await core.save()
        #expect(core.phase == .failure(ConnectionIdentityError.serverChanged.localizedDescription))
        #expect(factory.requestedBaseURLs.isEmpty)
        #expect(store.accounts == [account])
        #expect(store.tokens[account.id] == "original")
    }

    @Test
    func `name updates work offline without authenticating or scheduling recovery`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(displayName: "Home", baseURL: #require(URL(string: "https://tasks.example.com")))
        try await store.addAccount(account, token: "original")
        let factory = FakeInstanceClientFactory()
        factory.result = .failure(.offline)
        let core = makeCore(editingAccount: account, store: store, factory: factory)
        core.displayName = "Renamed"
        await core.saveName()
        #expect(core.phase == .success)
        #expect(store.accounts.first?.displayName == "Renamed")
        #expect(store.tokens[account.id] == "original")
        #expect(!core.didReplaceCredentials)
        #expect(factory.requestedBaseURLs.isEmpty)
    }

    @Test
    func `legacy identity binds once and a stale editor cannot bypass the binding`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(displayName: "Home", baseURL: #require(URL(string: "https://tasks.example.com")))
        try await store.addAccount(account, token: "original")
        let factory = FakeInstanceClientFactory()
        let core = makeCore(editingAccount: account, store: store, factory: factory)
        core.apiToken = "first-login"
        await core.save()
        #expect(store.accounts.first?.userID == 1)
        factory.authService.apiTokenUser = User(id: 2, username: "other")
        let stale = makeCore(editingAccount: account, store: store, factory: factory)
        stale.apiToken = "other-user"
        await stale.save()
        #expect(stale.savedAccount == nil)
        #expect(store.tokens[account.id] == "first-login")
        #expect(store.accounts.first?.userID == 1)
    }

    @Test
    func `late login cannot overwrite a newer accepted credential`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(displayName: "Home", baseURL: #require(URL(string: "https://tasks.example.com")), userID: 1)
        try await store.addAccount(account, token: "original")
        let factory = FakeInstanceClientFactory()
        factory.authService.beforeAPIResponse = { try? await store.updateAccount(account, token: "newer-login") }
        let core = makeCore(editingAccount: account, store: store, factory: factory)
        core.apiToken = "late-candidate"
        await core.save()
        #expect(core.phase == .failure(ConnectionIdentityError.sessionChanged.localizedDescription))
        #expect(store.tokens[account.id] == "newer-login")
        #expect(core.savedAccount == nil)
    }

    @Test
    func `cancellation after receiving a candidate cannot replace the stored session`() async throws {
        let store = FakeAccountStore()
        let account = try InstanceAccount(displayName: "Home", baseURL: #require(URL(string: "https://tasks.example.com")), userID: 1)
        try await store.addAccount(account, token: "original")
        let factory = FakeInstanceClientFactory()
        factory.authService.beforeAPIResponse = { withUnsafeCurrentTask { $0?.cancel() } }
        let core = makeCore(editingAccount: account, store: store, factory: factory)
        core.apiToken = "candidate"
        let operation = Task { await core.save() }
        await operation.value
        #expect(core.phase == .idle)
        #expect(core.savedAccount == nil)
        #expect(store.tokens[account.id] == "original")
        #expect(store.accounts == [account])
    }

    @Test(arguments: [VikunjaError.offline, .server(message: "User-read permission required", statusCode: 403)])
    func `a failed candidate user lookup never creates an unverified connection`(error: VikunjaError) async {
        let store = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        factory.authService.apiError = error
        let core = makeCore(store: store, factory: factory)
        core.displayName = "New connection"
        core.urlText = "https://tasks.example.com"
        core.apiToken = "candidate"
        await core.save()
        #expect(core.phase == .failure(error.displayMessage))
        #expect(core.savedAccount == nil)
        #expect(store.accounts.isEmpty)
        #expect(store.tokens.isEmpty)
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

    func replaceSession(
        _ account: InstanceAccount, token: String, expected: InstanceAccount, matchingToken: String?,
    ) async throws {
        guard try await fetchAccounts().contains(expected),
              try await self.token(forAccountID: expected.id) == matchingToken else {
            throw ConnectionIdentityError.sessionChanged
        }
        try expected.validateIdentity(of: account)
        try await updateAccount(account, token: token)
    }

    func updateSession(
        for account: InstanceAccount, matchingToken: String, token: String?, needsReauthentication: Bool,
    ) throws -> Bool {
        guard let index = accounts.firstIndex(where: { $0 == account }),
              tokens[account.id] == matchingToken else { return false }
        accounts[index].needsReauthentication = needsReauthentication
        if let token {
            tokens[account.id] = token
        }
        return true
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
    var apiTokenUser = User(id: 1, username: "sergio")
    var apiError: VikunjaError?
    var beforeAPIResponse: (@Sendable () async -> Void)?

    func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        loginCredentials.append(credentials)
        return try loginResult.get()
    }

    func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        if let apiError {
            throw apiError
        }
        await beforeAPIResponse?()
        return AuthSession(token: token, user: apiTokenUser)
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
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> ProjectRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskBulkUpdateRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskBulkUpdateRepositoryProtocol {
        fatalError("Bulk completion is not exercised by these tests")
    }

    func makeLabelRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> LabelRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskRelationRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskCommentRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskAttachmentRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("unused")
    }

    func makeUserRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("unused")
    }

    func makeBucketRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> BucketRepositoryProtocol {
        fatalError("unused")
    }

    func makeWebhookRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> WebhookRepositoryProtocol {
        fatalError("unused")
    }

    func makeFilterRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> FilterRepositoryProtocol {
        fatalError("unused")
    }
}
