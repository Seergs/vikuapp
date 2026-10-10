import Foundation
@testable import Settings
import VikunjaCore

/// Shared account id for notification tests, so a `FakeNotificationSettingsStore`
/// pre-seeded with settings lines up with the account id a test's
/// `NotificationsViewModel` is constructed with, without every call site
/// having to thread the same id through by hand.
let fakeAccountID = UUID()

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
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> ProjectRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeLabelRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> LabelRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskRelationRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskCommentRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeTaskAttachmentRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeUserRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeBucketRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> BucketRepositoryProtocol {
        fatalError("not exercised by Settings tests")
    }

    func makeWebhookRepository(
        baseURL _: URL,
        tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> WebhookRepositoryProtocol {
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

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project]
    var fetchError: VikunjaError?

    init(projects: [Project] = []) {
        self.projects = projects
    }

    func fetchProjects() async throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return projects
    }

    func fetchProject(id: Int) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id _: Int) async throws {}
}

final class FakeUserRepository: UserRepositoryProtocol, @unchecked Sendable {
    var user: User
    var fetchError: VikunjaError?
    var updateError: VikunjaError?
    private(set) var fetchCallCount = 0
    private(set) var updateDefaultProjectCallCount = 0
    private(set) var lastUpdatedDefaultProjectID: Int??

    init(user: User = User(id: 1, username: "alex")) {
        self.user = user
    }

    func fetchCurrentUser() async throws -> User {
        fetchCallCount += 1
        if let fetchError {
            throw fetchError
        }
        return user
    }

    func updateDefaultProject(id: Int?) async throws -> User {
        updateDefaultProjectCallCount += 1
        lastUpdatedDefaultProjectID = id
        if let updateError {
            throw updateError
        }
        user.defaultProjectID = id
        return user
    }
}

final class FakeDefaultProjectCaching: DefaultProjectCaching, @unchecked Sendable {
    private(set) var cached: CachedDefaultProject?
    private(set) var setCallCount = 0

    func cachedDefaultProject() -> CachedDefaultProject? {
        cached
    }

    func setCachedDefaultProject(_ project: CachedDefaultProject?) {
        setCallCount += 1
        cached = project
    }
}

final class FakeWebhookRepository: WebhookRepositoryProtocol, @unchecked Sendable {
    struct CreatedUserWebhook {
        let targetURL: URL
        let events: [WebhookEvent]
        let secret: String?
    }

    struct CreatedProjectWebhook {
        let projectID: Int
        let targetURL: URL
        let events: [WebhookEvent]
        let secret: String?
    }

    private(set) var userWebhooks: [Webhook]
    private(set) var projectWebhooks: [Int: [Webhook]]
    private var nextID = 1000

    var createdUserWebhooks: [CreatedUserWebhook] = []
    var createdProjectWebhooks: [CreatedProjectWebhook] = []
    var updatedUserWebhooks: [Webhook] = []
    var updatedProjectWebhooks: [(projectID: Int, webhook: Webhook)] = []
    var deletedUserWebhookIDs: [Int] = []
    var deletedProjectWebhookIDs: [(projectID: Int, webhookID: Int)] = []

    init(userWebhooks: [Webhook] = [], projectWebhooks: [Int: [Webhook]] = [:]) {
        self.userWebhooks = userWebhooks
        self.projectWebhooks = projectWebhooks
    }

    func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        projectWebhooks[projectID] ?? []
    }

    func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        createdProjectWebhooks.append(
            CreatedProjectWebhook(projectID: projectID, targetURL: targetURL, events: events, secret: secret),
        )
        let webhook = Webhook(id: nextID, targetURL: targetURL, events: events, projectID: projectID)
        nextID += 1
        projectWebhooks[projectID, default: []].append(webhook)
        return webhook
    }

    func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        updatedProjectWebhooks.append((projectID, webhook))
        if let index = projectWebhooks[projectID]?.firstIndex(where: { $0.id == webhook.id }) {
            projectWebhooks[projectID]?[index] = webhook
        }
        return webhook
    }

    func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        deletedProjectWebhookIDs.append((projectID, webhookID))
        projectWebhooks[projectID]?.removeAll { $0.id == webhookID }
    }

    func fetchAvailableEvents() async throws -> [WebhookEvent] {
        Array(WebhookEvent.allCases)
    }

    func fetchUserWebhooks() async throws -> [Webhook] {
        userWebhooks
    }

    func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        createdUserWebhooks.append(CreatedUserWebhook(targetURL: targetURL, events: events, secret: secret))
        let webhook = Webhook(id: nextID, targetURL: targetURL, events: events, userID: 1)
        nextID += 1
        userWebhooks.append(webhook)
        return webhook
    }

    func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        updatedUserWebhooks.append(webhook)
        if let index = userWebhooks.firstIndex(where: { $0.id == webhook.id }) {
            userWebhooks[index] = webhook
        }
        return webhook
    }

    func deleteUserWebhook(webhookID: Int) async throws {
        deletedUserWebhookIDs.append(webhookID)
        userWebhooks.removeAll { $0.id == webhookID }
    }

    func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        Array(WebhookEvent.userDirected)
    }
}

final class FakePushNotificationRegistering: PushNotificationRegistering, @unchecked Sendable {
    var enableResult: Result<PushRegistration?, Error> = .success(
        PushRegistration(targetURL: URL(string: "https://relay.example.com/h/device-1")!, secret: "test-secret"),
    )
    private(set) var enabledUserIDs: [Int] = []
    private(set) var disabledAccountIDs: [InstanceAccount.ID] = []
    var disableCallCount: Int {
        disabledAccountIDs.count
    }

    func enable(vikunjaUserID: Int, accountID: InstanceAccount.ID) async throws -> PushRegistration? {
        enabledUserIDs.append(vikunjaUserID)
        return try enableResult.get()
    }

    func disable(accountID: InstanceAccount.ID) async throws {
        disabledAccountIDs.append(accountID)
    }
}

@MainActor
final class FakeNotificationSettingsStore: NotificationSettingsStore {
    private var allSettings: [InstanceAccount.ID: NotificationSettings]
    private(set) var savedSettings: [NotificationSettings] = []

    init(settings: NotificationSettings = NotificationSettings(), accountID: InstanceAccount.ID = fakeAccountID) {
        self.allSettings = [accountID: settings]
    }

    func settings(for accountID: InstanceAccount.ID) -> NotificationSettings {
        allSettings[accountID] ?? NotificationSettings()
    }

    func save(_ settings: NotificationSettings, for accountID: InstanceAccount.ID) {
        allSettings[accountID] = settings
        savedSettings.append(settings)
    }
}

@MainActor
final class FakeAppIconBadgeStoring: AppIconBadgeStoring {
    private(set) var isEnabled: Bool
    private(set) var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        setEnabledCalls.append(enabled)
    }
}

@MainActor
final class FakeAppIconBadgePermissionRequesting: AppIconBadgePermissionRequesting {
    var requestAuthorizationResult = true
    var isAuthorizationDeniedResult = false
    private(set) var requestAuthorizationCallCount = 0

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func isAuthorizationDenied() async -> Bool {
        isAuthorizationDeniedResult
    }
}
