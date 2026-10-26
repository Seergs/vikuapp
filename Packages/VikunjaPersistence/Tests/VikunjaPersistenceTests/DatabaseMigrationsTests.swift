import Foundation
import GRDB
import Testing
@testable import VikunjaPersistence

struct DatabaseMigrationsTests {
    private func migratedDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(on: &migrator)
        try migrator.migrate(dbQueue)
        return dbQueue
    }

    @Test
    func `migrating twice is a no op`() throws {
        let dbQueue = try migratedDatabase()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(on: &migrator)
        try migrator.migrate(dbQueue)
    }

    @Test
    func `project table round trips a row with no remote id yet`() throws {
        let dbQueue = try migratedDatabase()
        let record = ProjectRecord(
            localID: UUID(),
            remoteID: nil,
            title: "Groceries",
            description: nil,
            isArchived: false,
            isFavorite: true,
            parentProjectLocalID: nil,
            position: 1,
            hexColor: "#ff0000",
            serverUpdatedAt: nil,
        )

        try dbQueue.write { db in try record.insert(db) }

        let fetched = try dbQueue.read { db in try ProjectRecord.fetchOne(db, key: record.localID) }
        #expect(fetched == record)
    }

    @Test
    func `project remoteID is unique`() throws {
        let dbQueue = try migratedDatabase()
        let first = ProjectRecord(
            localID: UUID(), remoteID: 42, title: "A", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        let second = ProjectRecord(
            localID: UUID(), remoteID: 42, title: "B", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )

        try dbQueue.write { db in try first.insert(db) }
        #expect(throws: DatabaseError.self) {
            try dbQueue.write { db in try second.insert(db) }
        }
    }

    @Test
    func `deleting a parent project nullifies the child's parent reference`() throws {
        let dbQueue = try migratedDatabase()
        let parent = ProjectRecord(
            localID: UUID(), remoteID: nil, title: "Parent", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        var child = ProjectRecord(
            localID: UUID(), remoteID: nil, title: "Child", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: parent.localID, position: 0, hexColor: "", serverUpdatedAt: nil,
        )

        try dbQueue.write { db in
            try parent.insert(db)
            try child.insert(db)
            try parent.delete(db)
        }

        child = try #require(dbQueue.read { db in try ProjectRecord.fetchOne(db, key: child.localID) })
        #expect(child.parentProjectLocalID == nil)
    }

    @Test
    func `mutation queue assigns an incrementing id on insert`() throws {
        let dbQueue = try migratedDatabase()
        var item = MutationQueueRecord(
            id: nil,
            entityType: .project,
            operation: .create,
            targetLocalID: UUID(),
            payload: #"{"title":"Groceries"}"#,
            createdAt: Date(),
            retryCount: 0,
            lastError: nil,
            status: .pending,
            needsConflictResolution: false,
        )

        try dbQueue.write { db in try item.insert(db) }
        #expect(item.id != nil)
    }

    @Test
    func `mutation queue status is constrained to known values`() throws {
        let dbQueue = try migratedDatabase()
        #expect(throws: DatabaseError.self) {
            try dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO mutationQueueItem
                        (entityType, operation, targetLocalID, createdAt, status)
                    VALUES ('project', 'create', ?, ?, 'bogus')
                    """,
                    arguments: [UUID().uuidString, Date()],
                )
            }
        }
    }
}
