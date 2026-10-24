import Foundation
import Testing
@testable import VikunjaPersistence

struct LocalStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test
    func `write then read round trips a project through the actor`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let record = ProjectRecord(
            localID: UUID(),
            remoteID: nil,
            title: "Groceries",
            description: nil,
            isArchived: false,
            isFavorite: false,
            parentProjectLocalID: nil,
            position: 0,
            hexColor: "",
            serverUpdatedAt: nil,
        )

        try await store.write { db in try record.insert(db) }
        let fetched = try await store.read { db in try ProjectRecord.fetchOne(db, key: record.localID) }

        #expect(fetched == record)
    }

    @Test
    func `data survives reopening the same directory`() async throws {
        let directory = temporaryDirectory()
        let record = ProjectRecord(
            localID: UUID(),
            remoteID: nil,
            title: "Groceries",
            description: nil,
            isArchived: false,
            isFavorite: false,
            parentProjectLocalID: nil,
            position: 0,
            hexColor: "",
            serverUpdatedAt: nil,
        )

        do {
            let store = try LocalStore(directory: directory)
            try await store.write { db in try record.insert(db) }
        }

        let reopened = try LocalStore(directory: directory)
        let fetched = try await reopened.read { db in try ProjectRecord.fetchOne(db, key: record.localID) }
        #expect(fetched == record)
    }
}
