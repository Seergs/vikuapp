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
            accountID: UUID(),
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
    func `project remoteID is unique within an account`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let first = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 42, title: "A", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        let second = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 42, title: "B", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )

        try dbQueue.write { db in try first.insert(db) }
        #expect(throws: DatabaseError.self) {
            try dbQueue.write { db in try second.insert(db) }
        }
    }

    @Test
    func `project remoteID can repeat across different accounts`() throws {
        let dbQueue = try migratedDatabase()
        let first = ProjectRecord(
            localID: UUID(), accountID: UUID(), remoteID: 42, title: "A", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        let second = ProjectRecord(
            localID: UUID(), accountID: UUID(), remoteID: 42, title: "B", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )

        try dbQueue.write { db in
            try first.insert(db)
            try second.insert(db)
        }

        let rows = try dbQueue.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.count == 2)
    }

    @Test
    func `deleting a parent project nullifies the child's parent reference`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let parent = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: nil, title: "Parent", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        var child = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: nil, title: "Child", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: parent.localID, position: 0, hexColor: "",
            serverUpdatedAt: nil,
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
            accountID: UUID(),
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
                        (accountID, entityType, operation, targetLocalID, createdAt, status)
                    VALUES (?, 'project', 'create', ?, ?, 'bogus')
                    """,
                    arguments: [UUID().uuidString, UUID().uuidString, Date()],
                )
            }
        }
    }

    @Test
    func `sync state is keyed per account so two accounts each get their own row`() throws {
        let dbQueue = try migratedDatabase()
        let first = SyncStateRecord(accountID: UUID(), entityType: .project, lastPulledAt: Date())
        let second = SyncStateRecord(accountID: UUID(), entityType: .project, lastPulledAt: Date())

        try dbQueue.write { db in
            try first.save(db)
            try second.save(db)
        }

        let rows = try dbQueue.read { db in try SyncStateRecord.fetchAll(db) }
        #expect(rows.count == 2)
    }

    @Test
    func `label table round trips a row with no remote id yet`() throws {
        let dbQueue = try migratedDatabase()
        let record = LabelRecord(localID: UUID(), accountID: UUID(), remoteID: nil, title: "Urgent", hexColor: "ff0000")

        try dbQueue.write { db in try record.insert(db) }

        let fetched = try dbQueue.read { db in try LabelRecord.fetchOne(db, key: record.localID) }
        #expect(fetched == record)
    }

    @Test
    func `label remoteID is unique within an account`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let first = LabelRecord(localID: UUID(), accountID: accountID, remoteID: 42, title: "A", hexColor: "")
        let second = LabelRecord(localID: UUID(), accountID: accountID, remoteID: 42, title: "B", hexColor: "")

        try dbQueue.write { db in try first.insert(db) }
        #expect(throws: DatabaseError.self) {
            try dbQueue.write { db in try second.insert(db) }
        }
    }

    @Test
    func `label remoteID can repeat across different accounts`() throws {
        let dbQueue = try migratedDatabase()
        let first = LabelRecord(localID: UUID(), accountID: UUID(), remoteID: 42, title: "A", hexColor: "")
        let second = LabelRecord(localID: UUID(), accountID: UUID(), remoteID: 42, title: "B", hexColor: "")

        try dbQueue.write { db in
            try first.insert(db)
            try second.insert(db)
        }

        let rows = try dbQueue.read { db in try LabelRecord.fetchAll(db) }
        #expect(rows.count == 2)
    }

    @Test
    func `task table round trips a row with no remote id yet`() throws {
        let dbQueue = try migratedDatabase()
        let project = ProjectRecord(
            localID: UUID(), accountID: UUID(), remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        let record = TaskRecord(
            localID: UUID(), accountID: project.accountID, remoteID: nil, title: "Buy milk", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID,
        )

        try dbQueue.write { db in
            try project.insert(db)
            try record.insert(db)
        }

        let fetched = try dbQueue.read { db in try TaskRecord.fetchOne(db, key: record.localID) }
        #expect(fetched == record)
    }

    @Test
    func `task remoteID is unique within an account`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        let first = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: 42, title: "A", description: nil, isDone: false,
            dueDate: nil, priority: 0, projectLocalID: project.localID,
        )
        let second = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: 42, title: "B", description: nil, isDone: false,
            dueDate: nil, priority: 0, projectLocalID: project.localID,
        )

        try dbQueue.write { db in
            try project.insert(db)
            try first.insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try dbQueue.write { db in try second.insert(db) }
        }
    }

    @Test
    func `task remoteID can repeat across different accounts`() throws {
        let dbQueue = try migratedDatabase()
        let projectA = ProjectRecord(
            localID: UUID(), accountID: UUID(), remoteID: 1, title: "A", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        let projectB = ProjectRecord(
            localID: UUID(), accountID: UUID(), remoteID: 1, title: "B", description: nil, isArchived: false,
            isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        let first = TaskRecord(
            localID: UUID(), accountID: projectA.accountID, remoteID: 42, title: "A", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: projectA.localID,
        )
        let second = TaskRecord(
            localID: UUID(), accountID: projectB.accountID, remoteID: 42, title: "B", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: projectB.localID,
        )

        try dbQueue.write { db in
            try projectA.insert(db)
            try projectB.insert(db)
            try first.insert(db)
            try second.insert(db)
        }

        let rows = try dbQueue.read { db in try TaskRecord.fetchAll(db) }
        #expect(rows.count == 2)
    }

    @Test
    func `deleting a project cascades to its cached tasks`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        let task = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: nil, title: "Buy milk", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID,
        )

        try dbQueue.write { db in
            try project.insert(db)
            try task.insert(db)
            try project.delete(db)
        }

        let rows = try dbQueue.read { db in try TaskRecord.fetchAll(db) }
        #expect(rows.isEmpty)
    }
}
