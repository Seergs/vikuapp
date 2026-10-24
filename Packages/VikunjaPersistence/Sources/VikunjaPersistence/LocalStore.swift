import Foundation
import GRDB

public enum LocalStoreError: Error, Sendable {
    /// The App Group container isn't available - the App Groups entitlement
    /// is missing, or the identifier doesn't match between targets.
    case containerUnavailable
}

/// Actor wrapping a GRDB `DatabasePool` (WAL mode, GRDB's default for that
/// type) around the offline-sync schema. All reads and writes to the local
/// SQLite database go through this actor, mirroring `URLSessionAPIClient`
/// being an actor rather than a class with locks.
public actor LocalStore {
    private let dbPool: DatabasePool

    /// - Parameter directory: where the database file lives, created if
    ///   missing. Pass the App Group container so a widget extension can
    ///   eventually read the same database; a scratch directory works for
    ///   tests.
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPool = try DatabasePool(path: directory.appendingPathComponent("viku.sqlite").path)
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(on: &migrator)
        try migrator.migrate(dbPool)
        self.dbPool = dbPool
    }

    public init(appGroupIdentifier: String) throws {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        )
        guard let directory else {
            throw LocalStoreError.containerUnavailable
        }
        try self.init(directory: directory)
    }

    public func read<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        try await dbPool.read(value)
    }

    public func write<T: Sendable>(_ updates: @Sendable (Database) throws -> T) async throws -> T {
        try await dbPool.write(updates)
    }
}
