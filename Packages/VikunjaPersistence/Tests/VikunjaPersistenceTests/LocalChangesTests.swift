import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor ChangeCounter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

struct LocalChangesTests {
    @Test
    func `observation emits initial content and local writes only for its account`() async throws {
        let store = try LocalStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        let accountA = UUID()
        let accountB = UUID()
        let counter = ChangeCounter()
        let stream = await store.observeChanges(accountID: accountA)
        let observer = Task {
            for try await _ in stream {
                await counter.increment()
            }
        }
        defer { observer.cancel() }
        await waitUntil { await counter.value == 1 }
        try await insertProject(accountID: accountB, title: "Other account", store: store)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await counter.value == 1)
        try await insertProject(accountID: accountA, title: "Observed", store: store)
        await waitUntil { await counter.value == 2 }
        #expect(await counter.value == 2)
        observer.cancel()
        _ = await observer.result
        try await insertProject(accountID: accountA, title: "After cancellation", store: store)
        #expect(await counter.value == 2)
    }

    private func insertProject(accountID: UUID, title: String, store: LocalStore) async throws {
        try await store.write { db in
            try ProjectRecord(
                localID: UUID(), accountID: accountID, remoteID: nil, title: title, description: nil,
                isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0,
                hexColor: "", serverUpdatedAt: nil,
            ).insert(db)
        }
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while await !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
