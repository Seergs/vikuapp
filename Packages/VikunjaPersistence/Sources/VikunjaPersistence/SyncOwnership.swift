import Darwin
import Foundation
import GRDB

/// Durable ownership, not a SQLite transaction held across networking. A live
/// owner is never displaced by a timeout: a suspended process may still have an
/// accepted request in flight. Only confirmed process death permits recovery.
struct SyncOwnership: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "syncOwnership"
    let accountID: UUID
    let token: UUID
    let processID: Int32
    let processStartedAt: String?

    init(accountID: UUID) {
        self.accountID = accountID
        self.token = UUID()
        self.processID = getpid()
        self.processStartedAt = Self.startTime(of: getpid())
    }

    private static let registry = Registry()

    func acquire(in store: LocalStore) async throws {
        Self.registry.insert(token)
        do {
            try await store.write { db in
                if let owner = try Self.fetchOne(db, key: accountID), owner.isAlive {
                    throw SyncOwnershipError.busy
                }
                try save(db)
            }
        } catch {
            Self.registry.remove(token)
            throw error
        }
    }

    func release(in store: LocalStore) async {
        // A cancelled worker still needs cleanup. If database execution has
        // already expired, leave the row: this process can reclaim it on resume.
        // Another live process must not guess that a suspended owner is dead.
        await Task.detached {
            try? await store.write { db in
                try db.execute(
                    sql: "DELETE FROM syncOwnership WHERE accountID = ? AND token = ?",
                    arguments: [accountID, token],
                )
            }
            Self.registry.remove(token)
        }.value
    }

    private var isAlive: Bool {
        if processID == getpid() {
            return Self.registry.contains(token)
        }
        if kill(processID, 0) == -1, errno == ESRCH {
            return false
        }
        if let expected = processStartedAt, let actual = Self.startTime(of: processID) {
            return expected == actual
        }
        // Sandbox restrictions and unknown process status fail closed.
        return true
    }

    private static func startTime(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let date = info.kp_proc.p_starttime
        return "\(date.tv_sec):\(date.tv_usec)"
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var active: Set<UUID> = []
        func insert(_ token: UUID) {
            lock.withLock { _ = active.insert(token) }
        }

        func remove(_ token: UUID) {
            lock.withLock { _ = active.remove(token) }
        }

        func contains(_ token: UUID) -> Bool {
            lock.withLock { active.contains(token) }
        }
    }
}

public enum SyncOwnershipError: Error, Sendable, LocalizedError {
    /// Another process owns this account. Local intent remains durable; retry
    /// on the next ordinary synchronization trigger instead of blocking the UI.
    case busy

    public var errorDescription: String? {
        String(localized: "Synchronization is already running. Try again shortly.", bundle: .module)
    }
}
