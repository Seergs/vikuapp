import GRDB

/// Registers every schema migration for the local offline store, in the
/// order they must run. `LocalStore` applies this migrator to its
/// `DatabasePool` on startup; GRDB tracks which migrations already ran
/// per-database, so this is idempotent.
///
/// Append-only: once a migration has shipped, never edit it, add a new one
/// instead. Later entities (Label, VikunjaTask, ...) each land as their own
/// additive migration here, not by editing `createProject`/
/// `createMutationQueue`.
enum DatabaseMigrations {
    static func registerAll(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("createProject", migrate: createProject)
        migrator.registerMigration("createMutationQueue", migrate: createMutationQueue)
        migrator.registerMigration("createSyncState", migrate: createSyncState)
        migrator.registerMigration("createLabel", migrate: createLabel)
        migrator.registerMigration("createTask", migrate: createTask)
    }

    private static func createProject(_ db: Database) throws {
        try db.create(table: "project") { table in
            table.primaryKey("localID", .text)
            // Every table here is keyed by `accountID` (`InstanceAccount.
            // id`) rather than living in its own per-account database file,
            // so a single `SyncCoordinator` can iterate every saved account
            // against one `LocalStore`. A project's `remoteID` is therefore
            // only unique within its own account, not across the table.
            table.column("accountID", .text).notNull().indexed()
            table.column("remoteID", .integer)
            table.column("title", .text).notNull()
            table.column("description", .text)
            table.column("isArchived", .boolean).notNull().defaults(to: false)
            table.column("isFavorite", .boolean).notNull().defaults(to: false)
            table.column("parentProjectLocalID", .text)
                .indexed()
                .references("project", column: "localID", onDelete: .setNull)
            table.column("position", .double).notNull().defaults(to: 0)
            table.column("hexColor", .text).notNull().defaults(to: "")
            // Vikunja's server `updated` timestamp as of the last successful
            // pull or push; nil until the networking layer decodes it
            // (today's `ProjectDTO` doesn't yet). Compared against on push
            // to detect a server-side edit the queued mutation wasn't
            // based on.
            table.column("serverUpdatedAt", .datetime)
        }
        try db.create(
            index: "project_on_accountID_remoteID",
            on: "project",
            columns: ["accountID", "remoteID"],
            unique: true,
        )
    }

    private static func createMutationQueue(_ db: Database) throws {
        try db.create(table: "mutationQueueItem") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("accountID", .text).notNull()
            table.column("entityType", .text).notNull()
            table.column("operation", .text).notNull()
            table.column("targetLocalID", .text).notNull().indexed()
            table.column("payload", .text)
            table.column("createdAt", .datetime).notNull()
            table.column("retryCount", .integer).notNull().defaults(to: 0)
            table.column("lastError", .text)
            table.column("status", .text).notNull().defaults(to: "pending")
                .check { ["pending", "inFlight", "failed"].contains($0) }
            // Set when a queued update conflicts with a newer server-side
            // edit the most recent pull observed. A conflicted row keeps
            // `status == "pending"` — it isn't a push failure, it's blocked
            // on a person choosing "keep mine" or "keep server" (not built
            // yet) — and the drain query excludes it by this flag instead.
            table.column("needsConflictResolution", .boolean).notNull().defaults(to: false)
        }
        // Queue drain scans one account's pending rows in FIFO order.
        try db.create(
            index: "mutationQueueItem_on_accountID_status_createdAt",
            on: "mutationQueueItem",
            columns: ["accountID", "status", "createdAt"],
        )
    }

    private static func createSyncState(_ db: Database) throws {
        // One row per account per entity type ("project", later "label"/
        // "task"/...), reusing the same free-text discriminator
        // `mutationQueueItem.entityType` already uses, so this table never
        // needs its own migration when a later slice adds an entity.
        try db.create(table: "syncState") { table in
            table.column("accountID", .text).notNull()
            table.column("entityType", .text).notNull()
            table.column("lastPulledAt", .datetime).notNull()
            table.primaryKey(["accountID", "entityType"])
        }
    }

    private static func createLabel(_ db: Database) throws {
        try db.create(table: "label") { table in
            table.primaryKey("localID", .text)
            // Same per-account scoping as `project` - see its own comment.
            table.column("accountID", .text).notNull().indexed()
            table.column("remoteID", .integer)
            table.column("title", .text).notNull()
            table.column("hexColor", .text).notNull().defaults(to: "")
        }
        try db.create(
            index: "label_on_accountID_remoteID",
            on: "label",
            columns: ["accountID", "remoteID"],
            unique: true,
        )
    }

    private static func createTask(_ db: Database) throws {
        try db.create(table: "task") { table in
            table.primaryKey("localID", .text)
            // Same per-account scoping as `project`/`label` - see `createProject`'s comment.
            table.column("accountID", .text).notNull().indexed()
            table.column("remoteID", .integer)
            table.column("title", .text).notNull()
            table.column("description", .text)
            table.column("isDone", .boolean).notNull().defaults(to: false)
            table.column("dueDate", .datetime)
            table.column("priority", .integer).notNull().defaults(to: 0)
            table.column("projectLocalID", .text)
                .notNull()
                .indexed()
                .references("project", column: "localID", onDelete: .cascade)
            // Vikunja's server `updated` timestamp as of the last successful
            // pull or push — same role as `createProject`'s own
            // `serverUpdatedAt` column, backing the task mutation queue's
            // conflict detection (`SyncEngine.drainTaskMutations`).
            table.column("serverUpdatedAt", .datetime)
        }
        try db.create(
            index: "task_on_accountID_remoteID",
            on: "task",
            columns: ["accountID", "remoteID"],
            unique: true,
        )
    }
}
