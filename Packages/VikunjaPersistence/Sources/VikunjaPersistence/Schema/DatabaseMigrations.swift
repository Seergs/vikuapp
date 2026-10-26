import GRDB

/// Registers every schema migration for the local offline store, in the
/// order they must run. `LocalStore` applies this migrator to its
/// `DatabasePool` on startup; GRDB tracks which migrations already ran
/// per-database, so this is idempotent.
///
/// Append-only: once a migration has shipped, never edit it, add a new one
/// instead. Per-account scoping and later entities (Label, VikunjaTask, ...)
/// each land as their own additive migration here, not by editing
/// `createProject`/`createMutationQueue`.
enum DatabaseMigrations {
    static func registerAll(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("createProject", migrate: createProject)
        migrator.registerMigration("createMutationQueue", migrate: createMutationQueue)
        migrator.registerMigration("createSyncState", migrate: createSyncState)
    }

    private static func createProject(_ db: Database) throws {
        try db.create(table: "project") { table in
            table.primaryKey("localID", .text)
            table.column("remoteID", .integer).unique()
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
    }

    private static func createMutationQueue(_ db: Database) throws {
        try db.create(table: "mutationQueueItem") { table in
            table.autoIncrementedPrimaryKey("id")
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
        // Queue drain scans pending rows in FIFO order.
        try db.create(
            index: "mutationQueueItem_on_status_createdAt",
            on: "mutationQueueItem",
            columns: ["status", "createdAt"],
        )
    }

    private static func createSyncState(_ db: Database) throws {
        // One row per entity type ("project", later "label"/"task"/...),
        // reusing the same free-text discriminator `mutationQueueItem.
        // entityType` already uses, so this table never needs its own
        // migration when a later slice adds an entity.
        try db.create(table: "syncState") { table in
            table.primaryKey("entityType", .text)
            table.column("lastPulledAt", .datetime).notNull()
        }
    }
}
