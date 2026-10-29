import Foundation
import GRDB
import Testing
import VikunjaCore
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
    func `saved filter migration backfills filters but not Favorites or real projects`() throws {
        let dbQueue = try DatabaseQueue()
        let accountID = UUID()
        let savedFilterLocalID = UUID()
        let favoritesLocalID = UUID()
        let realProjectLocalID = UUID()

        // Model the relevant columns from the existing project table before
        // the additive saved-filter migration runs.
        try dbQueue.write { db in
            try db.create(table: "project") { table in
                table.primaryKey("localID", .text)
                table.column("accountID", .text).notNull()
                table.column("remoteID", .integer)
            }
            try db.execute(
                sql: "INSERT INTO project (localID, accountID, remoteID) VALUES (?, ?, ?), (?, ?, ?), (?, ?, ?)",
                arguments: [
                    savedFilterLocalID, accountID, -8,
                    favoritesLocalID, accountID, -1,
                    realProjectLocalID, accountID, 23,
                ],
            )
            try DatabaseMigrations.createSavedFilter(db)
        }

        let rows = try dbQueue.read { db in try SavedFilterRecord.fetchAll(db) }
        #expect(rows == [SavedFilterRecord(
            projectLocalID: savedFilterLocalID,
            accountID: accountID,
            remoteID: 7,
            query: "",
            lastPulledAt: nil,
        )])
    }

    @Test
    func `saved filter detail composes presentation from project and query from cache`() {
        let record = SavedFilterRecord(
            projectLocalID: UUID(), accountID: UUID(), remoteID: 7,
            query: "priority >= 3", lastPulledAt: Date(),
        )
        let project = Project(
            id: .remote(-8), title: "Important", description: "Things to do",
            isFavorite: true, position: 2,
        )

        let detail = record.detail(project: project)

        #expect(detail == SavedFilterDetail(
            id: 7, title: "Important", description: "Things to do",
            isFavorite: true, query: "priority >= 3",
        ))
    }

    @Test
    func `saved filter detail rejects a project from another filter`() {
        let record = SavedFilterRecord(
            projectLocalID: UUID(), accountID: UUID(), remoteID: 7,
            query: "priority >= 3", lastPulledAt: Date(),
        )
        let otherProject = Project(id: .remote(-9), title: "Other")

        #expect(record.detail(project: otherProject) == nil)
    }

    @Test
    func `saved filter query can be read and persisted`() throws {
        let dbQueue = try migratedDatabase()
        let record = SavedFilterRecord(
            projectLocalID: UUID(), accountID: UUID(), remoteID: 7,
            query: "", lastPulledAt: nil,
        )
        let pulledAt = Date(timeIntervalSince1970: 1_700_000_000)

        try dbQueue.write { db in
            let project = ProjectRecord(
                localID: record.projectLocalID, accountID: record.accountID, remoteID: -8,
                title: "Important", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", serverUpdatedAt: nil,
            )
            try project.insert(db)
            try record.insert(db)
            var cached = try #require(try SavedFilterRecord.fetch(projectLocalID: record.projectLocalID, db: db))
            try cached.storeQuery("", pulledAt: pulledAt, db: db)
        }

        let cached = try dbQueue.read { db in
            try SavedFilterRecord.fetch(projectLocalID: record.projectLocalID, db: db)
        }
        #expect(cached?.query.isEmpty == true)
        #expect(cached?.lastPulledAt == pulledAt)
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

    @Test
    func `comment table round trips a row with no remote id yet`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        let task = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Buy milk", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID,
        )
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let record = TaskCommentRecord(
            localID: UUID(), accountID: accountID, remoteID: nil, taskLocalID: task.localID,
            comment: "Looks good", authorID: 7, authorUsername: "me", authorName: "Me", authorEmail: "me@example.com",
            created: created, updated: created,
        )

        try dbQueue.write { db in
            try project.insert(db)
            try task.insert(db)
            try record.insert(db)
        }

        let fetched = try dbQueue.read { db in try TaskCommentRecord.fetchOne(db, key: record.localID) }
        #expect(fetched == record)
    }

    @Test
    func `comment remoteID is unique within an account`() throws {
        let dbQueue = try migratedDatabase()
        let accountID = UUID()
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        let task = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Buy milk", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID,
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = TaskCommentRecord(
            localID: UUID(), accountID: accountID, remoteID: 42, taskLocalID: task.localID,
            comment: "A", authorID: 1, authorUsername: "me", authorName: nil, authorEmail: nil,
            created: now, updated: now,
        )
        let second = TaskCommentRecord(
            localID: UUID(), accountID: accountID, remoteID: 42, taskLocalID: task.localID,
            comment: "B", authorID: 1, authorUsername: "me", authorName: nil, authorEmail: nil,
            created: now, updated: now,
        )

        try dbQueue.write { db in
            try project.insert(db)
            try task.insert(db)
            try first.insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try dbQueue.write { db in try second.insert(db) }
        }
    }

    @Test
    func `deleting a task cascades to its cached comments`() throws {
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
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let comment = TaskCommentRecord(
            localID: UUID(), accountID: accountID, remoteID: nil, taskLocalID: task.localID,
            comment: "Looks good", authorID: 1, authorUsername: "me", authorName: nil, authorEmail: nil,
            created: now, updated: now,
        )

        try dbQueue.write { db in
            try project.insert(db)
            try task.insert(db)
            try comment.insert(db)
            try task.delete(db)
        }

        let rows = try dbQueue.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.isEmpty)
    }
}
