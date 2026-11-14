import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

actor MagicTestUserRepository: UserRepositoryProtocol {
    var mode: QuickAddMagicMode? = .vikunja
    var failure: (any Error)?
    var onFetch: (@Sendable () async throws -> Void)?
    var onUpdate: (@Sendable () async throws -> Void)?
    var updates: [QuickAddMagicMode] = []

    func configure(
        mode: QuickAddMagicMode? = .vikunja,
        failure: (any Error)? = nil,
        onFetch: (@Sendable () async throws -> Void)? = nil,
        onUpdate: (@Sendable () async throws -> Void)? = nil,
    ) {
        self.mode = mode
        self.failure = failure
        self.onFetch = onFetch
        self.onUpdate = onUpdate
    }

    func fetchCurrentUser() async throws -> User {
        if let failure {
            throw failure
        }
        let user = User(id: 3, username: "tester", quickAddMagicMode: mode)
        try await onFetch?()
        return user
    }

    func updateQuickAddMagicMode(_ mode: QuickAddMagicMode) async throws -> User {
        if let failure {
            throw failure
        }
        updates.append(mode)
        self.mode = mode
        let user = User(id: 3, username: "tester", quickAddMagicMode: mode)
        try await onUpdate?()
        return user
    }

    func updateDefaultProject(id: Int?) async throws -> User {
        try await fetchCurrentUser()
    }

    func updateOverdueTasksRemindersTime(_ time: String) async throws -> User {
        try await fetchCurrentUser()
    }
}

struct QuickAddSettingsTests {
    private func engine(store: LocalStore, accountID: UUID, users: MagicTestUserRepository) -> SyncEngine {
        SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(), userRepository: users, accountID: accountID,
        )
    }

    private func repository(store: LocalStore, accountID: UUID) -> OfflineQuickAddSettingsRepository {
        OfflineQuickAddSettingsRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
    }

    @Test func `unknown state differs from disabled and observations follow durable offline choices`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        var updates = await repository.observeSettings().makeAsyncIterator()
        #expect(try await updates.next() == QuickAddMagicSettings())
        try await repository.setMode(.disabled)
        #expect(try await updates.next() == QuickAddMagicSettings(mode: .disabled, syncStatus: .pending))
        let reopened = try LocalStore(directory: directory)
        let restored = self.repository(store: reopened, accountID: accountID)
        #expect(try await restored.settings() == QuickAddMagicSettings(mode: .disabled, syncStatus: .pending))
    }

    @Test func `remote refresh wins without pending intent and isolates accounts`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        let other = self.repository(store: store, accountID: UUID())
        try await other.setMode(.disabled)
        let users = MagicTestUserRepository()
        let engine = engine(store: store, accountID: accountID, users: users)
        try await engine.syncQuickAddSettings()
        #expect(try await repository.settings().mode == .vikunja)
        await users.configure(mode: .todoist)
        try await engine.syncQuickAddSettings()
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .todoist))
        #expect(try await other.settings() == QuickAddMagicSettings(mode: .disabled, syncStatus: .pending))
        #expect(await users.updates.isEmpty)
    }

    @Test func `offline choices coalesce and upload latest before accepting the server`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        try await repository.setMode(.disabled)
        try await repository.setMode(.vikunja)
        try await repository.setMode(.todoist)
        let queued = try await store.pendingSyncOperations(accountID: accountID)
        #expect(queued.count == 1)
        #expect(queued.first?.entity == .quickAddSettings)
        let users = MagicTestUserRepository()
        try await engine(store: store, accountID: accountID, users: users).syncQuickAddSettings()
        #expect(await users.updates == [.todoist])
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .todoist))
        #expect(try await store.pendingSyncOperations(accountID: accountID).isEmpty)
    }

    @Test func `failed upload survives restart and retries without losing the selected mode`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        try await repository.setMode(.todoist)
        let users = MagicTestUserRepository()
        await users.configure(failure: VikunjaError.offline)
        let engine = engine(store: store, accountID: accountID, users: users)
        await #expect(throws: VikunjaError.offline) { try await engine.syncQuickAddSettings() }
        let failed = try await repository.settings()
        #expect(failed.mode == .todoist)
        #expect(failed.syncStatus == .failed)
        #expect(failed.failureMessage != nil)
        let reopened = try LocalStore(directory: directory)
        #expect(try await self.repository(store: reopened, accountID: accountID).settings() == failed)
        await users.configure()
        try await self.engine(store: reopened, accountID: accountID, users: users).syncQuickAddSettings()
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .todoist))
    }

    @Test func `a selection during a remote read cannot be overwritten by that read`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        let users = MagicTestUserRepository()
        await users.configure(onFetch: { try await repository.setMode(.todoist) })
        try await engine(store: store, accountID: accountID, users: users).syncQuickAddSettings()
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .todoist, syncStatus: .pending))
    }

    @Test func `an old upload response cannot acknowledge a newer choice even with the same value`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        try await repository.setMode(.todoist)
        let users = MagicTestUserRepository()
        await users.configure(onUpdate: {
            try await repository.setMode(.disabled)
            try await repository.setMode(.todoist)
        })
        let engine = engine(store: store, accountID: accountID, users: users)
        try await engine.syncQuickAddSettings()
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .todoist, syncStatus: .pending))
        await users.configure()
        try await engine.syncQuickAddSettings()
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .todoist))
        #expect(await users.updates == [.todoist, .todoist])
    }

    @Test func `an old failed upload cannot mark a newer choice as failed`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        try await repository.setMode(.todoist)
        let users = MagicTestUserRepository()
        await users.configure(onUpdate: {
            try await repository.setMode(.disabled)
            throw VikunjaError.offline
        })
        let engine = engine(store: store, accountID: accountID, users: users)
        await #expect(throws: VikunjaError.offline) { try await engine.syncQuickAddSettings() }
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .disabled, syncStatus: .pending))
        await users.configure()
        try await engine.syncQuickAddSettings()
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .disabled))
    }

    @Test func `failed initial read and cancellation preserve cached values and pending choices`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        let users = MagicTestUserRepository()
        let engine = engine(store: store, accountID: accountID, users: users)
        await users.configure(failure: VikunjaError.offline)
        await #expect(throws: VikunjaError.offline) { try await engine.syncQuickAddSettings() }
        #expect(try await repository.settings() == QuickAddMagicSettings())
        await users.configure()
        try await engine.syncQuickAddSettings()
        await users.configure(failure: VikunjaError.offline)
        await #expect(throws: VikunjaError.offline) { try await engine.syncQuickAddSettings() }
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .vikunja))
        try await repository.setMode(.disabled)
        await users.configure(failure: CancellationError())
        await #expect(throws: CancellationError.self) { try await engine.syncQuickAddSettings() }
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .disabled, syncStatus: .pending))
    }

    @Test func `account replacement discards pending magic only after a successful download`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let repository = repository(store: store, accountID: accountID)
        try await repository.setMode(.todoist)
        _ = try await store.beginAccountReload(accountID: accountID)
        await #expect(throws: LocalStoreError.self) { try await repository.setMode(.disabled) }
        #expect(try await repository.settings().mode == .todoist)
        await store.endAccountReload(accountID: accountID)
        let emptyDirectory = directory.appendingPathComponent("staging")
        let staging = try LocalStore(directory: emptyDirectory)
        let users = MagicTestUserRepository()
        try await engine(store: staging, accountID: accountID, users: users).syncQuickAddSettings()
        let replacement = try await staging.read { db in try AccountSnapshot(accountID: accountID, db: db) }
        try await store.replaceAccount(accountID: accountID, with: replacement)
        #expect(try await repository.settings() == QuickAddMagicSettings(mode: .vikunja))
        #expect(try await store.pendingSyncOperations(accountID: accountID).isEmpty)
    }
}
