import Foundation
@testable import Settings
import VikunjaCore

final class FakeAccountStore: AccountStoreProtocol, @unchecked Sendable {
    private(set) var accounts: [InstanceAccount] = []
    private(set) var tokens: [InstanceAccount.ID: String] = [:]
    private var activeID: InstanceAccount.ID?

    var fetchAccountsError: VikunjaError?
    var setActiveError: VikunjaError?
    var removeError: VikunjaError?
    var updateError: VikunjaError?

    func fetchAccounts() async throws -> [InstanceAccount] {
        if let fetchAccountsError {
            throw fetchAccountsError
        }
        return accounts
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
        if let updateError {
            throw updateError
        }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw VikunjaError.notFound
        }
        accounts[index] = account
        if let token {
            tokens[account.id] = token
        }
    }

    func removeAccount(id: InstanceAccount.ID) async throws {
        if let removeError {
            throw removeError
        }
        accounts.removeAll { $0.id == id }
        tokens[id] = nil
        if activeID == id {
            activeID = accounts.first?.id
        }
    }

    func setActiveAccount(id: InstanceAccount.ID) async throws {
        if let setActiveError {
            throw setActiveError
        }
        guard accounts.contains(where: { $0.id == id }) else { throw VikunjaError.notFound }
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
    var result: Result<String, Error> = .failure(VikunjaError.network("not configured"))
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
        fatalError("not exercised by Settings tests")
    }

    func makeTaskRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeLabelRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> LabelRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskRelationRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskCommentRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskAttachmentRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeUserRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }
}

final class FakeLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    private(set) var labels: [Label]
    private var nextID: Int
    private(set) var deletedIDs: [Int] = []

    var fetchError: VikunjaError?
    var createError: VikunjaError?
    var updateError: VikunjaError?
    var deleteError: VikunjaError?

    init(labels: [Label] = []) {
        self.labels = labels
        self.nextID = (labels.map(\.id).max() ?? 0) + 1
    }

    func fetchLabels() async throws -> [Label] {
        if let fetchError {
            throw fetchError
        }
        return labels
    }

    func create(_ label: Label) async throws -> Label {
        if let createError {
            throw createError
        }
        let created = Label(id: nextID, title: label.title, hexColor: label.hexColor)
        nextID += 1
        labels.append(created)
        return created
    }

    func update(_ label: Label) async throws -> Label {
        if let updateError {
            throw updateError
        }
        guard let index = labels.firstIndex(where: { $0.id == label.id }) else {
            throw VikunjaError.notFound
        }
        labels[index] = label
        return label
    }

    func delete(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        labels.removeAll { $0.id == id }
        deletedIDs.append(id)
    }

    func addLabel(_: Int, toTask _: Int) async throws {
        fatalError("not exercised by Settings tests")
    }

    func removeLabel(_: Int, fromTask _: Int) async throws {
        fatalError("not exercised by Settings tests")
    }
}

final class FakeToastPresenter: ToastPresenting, @unchecked Sendable {
    private(set) var shownMessages: [(message: String, style: ToastStyle)] = []

    func show(_ message: String, style: ToastStyle) {
        shownMessages.append((message, style))
    }
}
