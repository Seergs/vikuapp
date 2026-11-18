import Foundation
import GRDB
import Testing
@testable import VikunjaPersistence

struct SyncOwnershipTests {
    @Test func `two connections exclude the same account but not other accounts`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try LocalStore(directory: directory)
        let widget = try LocalStore(directory: directory)
        let account = UUID()
        let first = SyncOwnership(accountID: account)
        let second = SyncOwnership(accountID: account)
        let other = SyncOwnership(accountID: UUID())
        try await first.acquire(in: app)
        await #expect(throws: SyncOwnershipError.self) { try await second.acquire(in: widget) }
        try await other.acquire(in: widget)
        await other.release(in: widget)
        await first.release(in: app)
        try await second.acquire(in: widget)
        await second.release(in: widget)
    }

    #if os(macOS)
    @Test func `a live process is never displaced but termination allows recovery`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer {
            if process.isRunning {
                process.terminate(); process.waitUntilExit()
            }
        }
        let account = UUID()
        let pid = process.processIdentifier
        try await store.write { db in
            try db.execute(sql: "INSERT INTO syncOwnership VALUES (?, ?, ?, NULL)", arguments: [account, UUID(), pid])
        }
        let candidate = SyncOwnership(accountID: account)
        await #expect(throws: SyncOwnershipError.self) { try await candidate.acquire(in: store) }
        process.terminate()
        process.waitUntilExit()
        try await candidate.acquire(in: store)
        await candidate.release(in: store)
    }

    #endif

    @Test func `cancelled worker cleanup permits the next owner`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(directory: directory)
        let account = UUID()
        let first = SyncOwnership(accountID: account)
        try await first.acquire(in: store)
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await first.release(in: store)
        }
        await worker.value
        let second = SyncOwnership(accountID: account)
        try await second.acquire(in: store)
        await second.release(in: store)
    }
}
