import Foundation
@testable import Onboarding
import VikunjaCore

final class FakeAccountStore: AccountStoreProtocol, @unchecked Sendable {
    private(set) var accounts: [InstanceAccount] = []
    private(set) var tokens: [InstanceAccount.ID: String] = [:]
    private var activeID: InstanceAccount.ID?
    var addAccountCallCount = 0

    func fetchAccounts() async throws -> [InstanceAccount] {
        accounts
    }

    func activeAccount() async throws -> InstanceAccount? {
        accounts.first { $0.id == activeID }
    }

    func addAccount(_ account: InstanceAccount, token: String) async throws {
        addAccountCallCount += 1
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        tokens[account.id] = token
        activeID = account.id
    }

    func updateAccount(_ account: InstanceAccount, token: String?) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw VikunjaError.notFound
        }
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

struct FakeCapabilityProvider: CapabilityProvider {
    var result: Result<VikunjaServerInfo, VikunjaError>
    var supportsLocalAuth = false

    func serverInfo() async throws -> VikunjaServerInfo {
        try result.get()
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        switch feature {
        case .localAuth:
            supportsLocalAuth
        default:
            false
        }
    }
}

final class FakeAuthService: AuthServiceProtocol, @unchecked Sendable {
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

final class FakeOIDCAuthenticating: OIDCAuthenticating, @unchecked Sendable {
    var result: Result<String, VikunjaError> = .failure(.network("not configured"))
    private(set) var requestedProviders: [OIDCProvider] = []
    private(set) var requestedRedirectURIs: [URL] = []

    func authenticate(provider: OIDCProvider, redirectURI: URL) async throws -> String {
        requestedProviders.append(provider)
        requestedRedirectURIs.append(redirectURI)
        return try result.get()
    }
}

final class FakeInstanceClientFactory: InstanceClientFactoryProtocol, @unchecked Sendable {
    var result: Result<VikunjaServerInfo, VikunjaError> = .success(
        VikunjaServerInfo(version: "0.24.6", caldavEnabled: false, totpEnabled: false, registrationEnabled: false),
    )
    var supportsLocalAuth = false
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
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> ProjectRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }

    func makeTaskRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }

    func makeLabelRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> LabelRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }

    func makeTaskRelationRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }

    func makeTaskCommentRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }

    func makeTaskAttachmentRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }

    func makeUserRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("not exercised by Onboarding tests")
    }
}
