import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor MetadataRemote: TaskAttachmentRepositoryProtocol {
    var attachments: [TaskAttachment] = []
    var failure: (any Error)?
    private var heldFetch: CheckedContinuation<[TaskAttachment], any Error>?
    private var fetchStarted: CheckedContinuation<Void, Never>?
    private var shouldHold = false
    private var downloads = 0
    private var requests = 0

    func requestCount() -> Int {
        requests
    }

    private var holdWrite = false
    private var heldWrite: CheckedContinuation<Void, Never>?
    private var writeStarted: CheckedContinuation<Void, Never>?

    func holdNextWrite() {
        holdWrite = true
    }

    func waitForWrite() async {
        if heldWrite != nil {
            return
        }
        await withCheckedContinuation { writeStarted = $0 }
    }

    func releaseWrite() {
        heldWrite?.resume()
        heldWrite = nil
    }

    private func pauseWriteIfNeeded() async {
        guard holdWrite else { return }
        holdWrite = false
        await withCheckedContinuation {
            heldWrite = $0
            writeStarted?.resume()
            writeStarted = nil
        }
    }

    func configure(_ attachments: [TaskAttachment], failure: (any Error)? = nil) {
        self.attachments = attachments
        self.failure = failure
    }

    func holdNextFetch() {
        shouldHold = true
    }

    func waitForFetch() async {
        if heldFetch != nil {
            return
        }
        await withCheckedContinuation { fetchStarted = $0 }
    }

    func releaseFetch(_ attachments: [TaskAttachment]) {
        heldFetch?.resume(returning: attachments)
        heldFetch = nil
    }

    func downloadCount() -> Int {
        downloads
    }

    func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        requests += 1
        if shouldHold {
            shouldHold = false
            return try await withCheckedThrowingContinuation {
                heldFetch = $0
                fetchStarted?.resume()
                fetchStarted = nil
            }
        }
        if let failure {
            throw failure
        }
        return attachments
    }

    func uploadAttachment(
        data: Data, fileName: String, mimeType: String, toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        requests += 1
        await pauseWriteIfNeeded()
        if let failure {
            throw failure
        }
        return [TaskAttachment(
            id: 99, taskID: taskID, fileName: fileName, mimeType: mimeType, sizeBytes: data.count,
            created: Date(timeIntervalSince1970: 100), createdBy: User(id: 7, username: "sam"),
        )]
    }

    func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        requests += 1
        await pauseWriteIfNeeded()
        if let failure {
            throw failure
        }
    }

    func downloadAttachment(
        _ id: Int, fromTask taskID: Int, previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        requests += 1
        downloads += 1
        return Data("file bytes".utf8)
    }
}

private actor AttachmentReachability: ReachabilityMonitoring {
    var isReachable = false
    func setOnline(_ online: Bool) {
        isReachable = online
    }

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

struct CachedTaskAttachmentRepositoryTests {
    private struct Fixture {
        let directory: URL
        let store: LocalStore
        let accountID: UUID
        let task: TaskRecord
        let remote: MetadataRemote
        let repository: CachedTaskAttachmentRepository
    }

    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let task = try await seedTask(store: store, accountID: accountID)
        let remote = MetadataRemote()
        return Fixture(
            directory: directory, store: store, accountID: accountID, task: task, remote: remote,
            repository: CachedTaskAttachmentRepository(localStore: store, accountID: accountID, remote: remote),
        )
    }

    private func seedTask(store: LocalStore, accountID: UUID, remoteID: Int = 42) async throws -> TaskRecord {
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: remoteID, title: "Project", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0,
            hexColor: "", serverUpdatedAt: nil,
        )
        let task = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: remoteID, title: "Task", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID,
        )
        try await store.write { db in
            try project.insert(db)
            try task.insert(db)
        }
        return task
    }

    private func attachment(_ id: Int = 1) -> TaskAttachment {
        TaskAttachment(
            id: id, taskID: 42, fileName: "spec-\(id).pdf", mimeType: "application/pdf", sizeBytes: 2048,
            created: Date(timeIntervalSince1970: 100),
            createdBy: User(id: 7, username: "sam", name: "Sam", email: "sam@example.com"),
        )
    }

    @Test(arguments: [false, true])
    func `complete catalogs including empty ones survive reopening without downloading files`(empty: Bool) async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == nil)
        let expected = empty ? [] : [attachment(2), attachment(1)]
        await context.remote.configure(expected)
        #expect(try await context.repository.fetchAttachments(taskID: 42) == expected)
        let reopened = try CachedTaskAttachmentRepository(
            localStore: LocalStore(directory: context.directory), accountID: context.accountID, remote: context.remote,
        )
        let snapshot = try #require(await reopened.cachedAttachmentSnapshot(taskID: 42))
        #expect(snapshot.attachments == expected)
        #expect(snapshot.lastSuccessfulDownloadAt != nil)
        #expect(await context.remote.downloadCount() == 0)
    }

    @Test
    func `metadata is isolated by account and task and full refresh replaces removed entries`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([attachment()])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        let otherAccount = UUID()
        _ = try await seedTask(store: context.store, accountID: otherAccount)
        _ = try await seedTask(store: context.store, accountID: context.accountID, remoteID: 43)
        let other = CachedTaskAttachmentRepository(
            localStore: context.store, accountID: otherAccount, remote: context.remote,
        )
        #expect(try await other.cachedAttachmentSnapshot(taskID: 42) == nil)
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 43) == nil)
        await context.remote.configure([])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42)?.attachments.isEmpty == true)
    }

    @Test
    func `failed or cancelled refresh keeps the previous catalog and coverage`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([attachment()])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        let before = try await context.repository.cachedAttachmentSnapshot(taskID: 42)
        await context.remote.holdNextFetch()
        let read = Task { try await context.repository.fetchAttachments(taskID: 42) }
        await context.remote.waitForFetch()
        read.cancel()
        // The transport may finish after cancellation; those results must not commit.
        await context.remote.releaseFetch([])
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == before)
        await context.remote.configure([], failure: VikunjaError.offline)
        await #expect(throws: VikunjaError.self) { try await context.repository.fetchAttachments(taskID: 42) }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == before)
    }

    @Test
    func `successful writes persist metadata while failures leave it unchanged`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let created = try await context.repository.uploadAttachment(
            data: Data("hello".utf8), fileName: "notes.txt", mimeType: "text/plain", toTask: 42,
        )
        let partial = try #require(await context.repository.cachedAttachmentSnapshot(taskID: 42))
        #expect(partial.attachments == created)
        #expect(partial.lastSuccessfulDownloadAt == nil)
        await context.remote.configure(created)
        _ = try await context.repository.fetchAttachments(taskID: 42)
        let before = try await context.repository.cachedAttachmentSnapshot(taskID: 42)
        await context.remote.configure([], failure: VikunjaError.offline)
        await #expect(throws: VikunjaError.self) { try await context.repository.deleteAttachment(99, fromTask: 42) }
        await #expect(throws: VikunjaError.self) {
            try await context.repository.uploadAttachment(
                data: Data(), fileName: "x", mimeType: "text/plain", toTask: 42,
            )
        }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == before)
        await context.remote.configure([])
        try await context.repository.deleteAttachment(99, fromTask: 42)
        let after = try #require(await context.repository.cachedAttachmentSnapshot(taskID: 42))
        #expect(after.attachments.isEmpty)
        #expect(after.lastSuccessfulDownloadAt == before?.lastSuccessfulDownloadAt)
    }

    @Test(arguments: [false, true])
    func `a late read from another repository cannot undo a successful write`(delete: Bool) async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let initial = [attachment()]
        await context.remote.configure(initial)
        _ = try await context.repository.fetchAttachments(taskID: 42)
        let another = CachedTaskAttachmentRepository(
            localStore: context.store, accountID: context.accountID, remote: context.remote,
        )
        await context.remote.holdNextFetch()
        let read = Task { try await another.fetchAttachments(taskID: 42) }
        await context.remote.waitForFetch()
        if delete {
            try await context.repository.deleteAttachment(1, fromTask: 42)
        } else {
            _ = try await context.repository.uploadAttachment(
                data: Data(), fileName: "x", mimeType: "text/plain", toTask: 42,
            )
        }
        let updated = try await context.repository.cachedAttachmentSnapshot(taskID: 42)
        await context.remote.releaseFetch(initial)
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(try await another.cachedAttachmentSnapshot(taskID: 42) == updated)
        #expect(updated?.attachments.map(\.id) == (delete ? [] : [1, 99]))
    }

    @Test
    func `a newer complete refresh wins over an older response`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.holdNextFetch()
        let first = Task { try await context.repository.fetchAttachments(taskID: 42) }
        await context.remote.waitForFetch()
        await context.remote.configure([attachment(2)])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        await context.remote.releaseFetch([attachment(1)])
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42)?.attachments == [attachment(2)])
    }

    @Test(arguments: [false, true])
    func `task deletion and account replacement discard metadata and reject late reads`(replaceAccount: Bool) async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([attachment()])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        await context.remote.holdNextFetch()
        let read = Task { try await context.repository.fetchAttachments(taskID: 42) }
        await context.remote.waitForFetch()
        if replaceAccount {
            let staging = try LocalStore(directory: context.directory.appendingPathComponent("staging"))
            let snapshot = try await staging.read { try AccountSnapshot(accountID: context.accountID, db: $0) }
            try await context.store.replaceAccount(accountID: context.accountID, with: snapshot)
        } else {
            _ = try await context.store.write { try context.task.delete($0) }
        }
        await context.remote.releaseFetch([attachment()])
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == nil)
        #expect(try await context.store.read { try TaskAttachmentRecord.fetchCount($0) } == 0)
        #expect(try await context.store.read { try TaskAttachmentCatalogRecord.fetchCount($0) } == 0)
    }

    @Test
    func `account reload rejects metadata writes before contacting the server`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try await context.store.beginAccountReload(accountID: context.accountID)
        await #expect(throws: LocalStoreError.self) { try await context.repository.fetchAttachments(taskID: 42) }
        await context.store.endAccountReload(accountID: context.accountID)
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == nil)
    }

    @Test(arguments: [false, true])
    func `a read started during an upload or deletion cannot overwrite its confirmation`(delete: Bool) async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let initial = [attachment()]
        await context.remote.configure(initial)
        _ = try await context.repository.fetchAttachments(taskID: 42)
        await context.remote.holdNextWrite()
        let write = Task {
            if delete {
                try await context.repository.deleteAttachment(1, fromTask: 42)
            } else {
                _ = try await context.repository.uploadAttachment(
                    data: Data(), fileName: "x", mimeType: "text/plain", toTask: 42,
                )
            }
        }
        await context.remote.waitForWrite()
        await context.remote.holdNextFetch()
        let read = Task { try await context.repository.fetchAttachments(taskID: 42) }
        await context.remote.waitForFetch()
        await context.remote.releaseWrite()
        try await write.value
        await context.remote.releaseFetch(initial)
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42)?.attachments.map(\.id)
            == (delete ? [] : [1, 99]))
    }

    @Test
    func `failed first download never establishes an empty catalog`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([], failure: VikunjaError.offline)
        await #expect(throws: VikunjaError.self) { try await context.repository.fetchAttachments(taskID: 42) }
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42) == nil)
        await context.remote.configure([])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42)?.lastSuccessfulDownloadAt != nil)
    }

    @Test(arguments: [false, true])
    func `cancellation after server confirmation does not report a failed mutation or lose its metadata`(
        delete: Bool,
    ) async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([attachment()])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        await context.remote.holdNextWrite()
        let write = Task {
            if delete {
                try await context.repository.deleteAttachment(1, fromTask: 42)
            } else {
                _ = try await context.repository.uploadAttachment(
                    data: Data(), fileName: "x", mimeType: "text/plain", toTask: 42,
                )
            }
        }
        await context.remote.waitForWrite()
        write.cancel()
        await context.remote.releaseWrite()
        try await write.value
        let cached = try await context.repository.cachedAttachmentSnapshot(taskID: 42)
        #expect(cached?.attachments.map(\.id) == (delete ? [] : [1, 99]))
    }

    @Test
    func `account recovery rejecting reconciliation does not report a confirmed server deletion as failed`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([attachment()])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        await context.remote.holdNextWrite()
        let write = Task { try await context.repository.deleteAttachment(1, fromTask: 42) }
        await context.remote.waitForWrite()
        _ = try await context.store.beginAccountReload(accountID: context.accountID)
        await context.remote.releaseWrite()
        try await write.value
        await context.store.endAccountReload(accountID: context.accountID)
        // The reload guard preserves the snapshot until recovery finishes.
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42)?.attachments == [attachment()])
        await context.remote.configure([])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        #expect(try await context.repository.cachedAttachmentSnapshot(taskID: 42)?.attachments.isEmpty == true)
    }

    @Test(arguments: ["catalog", "download", "upload", "delete"])
    func `known offline requests fail before reaching the transport and can retry after reconnection`(
        operation: String,
    ) async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.remote.configure([attachment()])
        _ = try await context.repository.fetchAttachments(taskID: 42)
        let saved = try await context.repository.cachedAttachmentSnapshot(taskID: 42)
        let requests = await context.remote.requestCount()
        let monitor = AttachmentReachability()
        let repository = CachedTaskAttachmentRepository(
            localStore: context.store, accountID: context.accountID, remote: context.remote, reachability: monitor,
        )
        await #expect(throws: VikunjaError.offline) {
            switch operation {
            case "catalog": _ = try await repository.fetchAttachments(taskID: 42)
            case "download": _ = try await repository.downloadAttachment(1, fromTask: 42, previewSize: nil)
            case "upload":
                _ = try await repository.uploadAttachment(
                    data: Data(), fileName: "notes.txt", mimeType: "text/plain", toTask: 42,
                )
            default: try await repository.deleteAttachment(1, fromTask: 42)
            }
        }
        #expect(await context.remote.requestCount() == requests)
        #expect(try await repository.cachedAttachmentSnapshot(taskID: 42) == saved)
        await monitor.setOnline(true)
        #expect(try await repository.fetchAttachments(taskID: 42) == [attachment()])
        #expect(try await repository.downloadAttachment(1, fromTask: 42, previewSize: nil) == Data("file bytes".utf8))
        #expect(await context.remote.requestCount() == requests + 2)
    }

    @Test
    func `unknown startup connectivity allows an explicit request instead of assuming offline`() async throws {
        let context = try await fixture()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let path = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: path, queue: .main)
        let repository = CachedTaskAttachmentRepository(
            localStore: context.store, accountID: context.accountID, remote: context.remote, reachability: monitor,
        )
        #expect(await monitor.isReachable == false)
        #expect(await monitor.isKnownOffline == false)
        _ = try await repository.fetchAttachments(taskID: 42)
        #expect(await context.remote.requestCount() == 1)
    }
}
