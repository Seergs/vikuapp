import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

@Suite(.timeLimit(.minutes(1)))
struct SharedStoreNotificationTests {
    @Test func `another connection invalidates existing screen observations`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try LocalStore(directory: directory)
        let widget = try LocalStore(directory: directory)
        let accountID = UUID()
        let stream = await app.observeChanges(accountID: accountID)
        var events = stream.makeAsyncIterator()
        _ = try await events.next()
        let repository = OfflineProjectRepository(
            localStore: widget, accountID: accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await repository.create(Project(id: .local(UUID()), title: "Written by another connection"))
        // Ownership changes are excluded from content observations; this event
        // represents actual account data committed by the other connection.
        #expect(try await events.next() != nil)
        let appRepository = OfflineProjectRepository(
            localStore: app, accountID: accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await appRepository.fetchProjects().map(\.title) == ["Written by another connection"])
    }

    @Test func `account replacement cannot discard an edit from the extension`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try LocalStore(directory: directory)
        let widget = try LocalStore(directory: directory)
        let accountID = UUID()
        let original = try await app.read { db in try AccountSnapshot(accountID: accountID, db: db) }
        let repository = OfflineProjectRepository(
            localStore: widget, accountID: accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await repository.create(Project(id: .local(UUID()), title: "Keep my edit"))
        await #expect(throws: LocalStoreError.self) {
            try await app.replaceAccount(accountID: accountID, with: original, expecting: original)
        }
        #expect(try await repository.fetchProjects().map(\.title) == ["Keep my edit"])
        #expect(try await widget.pendingSyncOperations(accountID: accountID).count == 1)
    }
}
