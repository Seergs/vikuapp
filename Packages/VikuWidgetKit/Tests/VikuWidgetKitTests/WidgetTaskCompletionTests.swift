import Foundation
import Testing
import VikunjaCore
@testable import VikuWidgetKit

struct WidgetTaskCompletionTests {
    @Test func `local acceptance reloads before sync and remains successful after upload failure`() async throws {
        let state = CompletionEvents()
        let completion = WidgetTaskCompletion(repository: state, synchronize: {
            await state.append("sync")
            throw VikunjaError.offline
        }, reload: { await state.append("reload") })
        try await completion.setCompletion(taskID: 10, isDone: true)
        #expect(await state.events == ["save:10:true", "reload", "sync"])
        #expect(await state.isDone)
    }

    @Test func `replaying an old timeline submits the same target instead of toggling back`() async throws {
        let state = CompletionEvents()
        let completion = WidgetTaskCompletion(repository: state, synchronize: {}, reload: {})
        try await completion.setCompletion(taskID: 10, isDone: true)
        try await completion.setCompletion(taskID: 10, isDone: true)
        #expect(await state.isDone)
    }

    @Test func `local rejection does not upload or report a successful reload`() async {
        let state = CompletionEvents(reject: true)
        let completion = WidgetTaskCompletion(repository: state, synchronize: {
            Issue.record("Uploaded a rejected local mutation")
        }, reload: { Issue.record("Published a rejected mutation") })
        await #expect(throws: VikunjaError.self) { try await completion.setCompletion(taskID: 10, isDone: true) }
        #expect(await !state.isDone)
    }

    @Test func `deadline cancels the network operation before returning`() async {
        let state = CompletionEvents()
        await #expect(throws: CancellationError.self) {
            try await WidgetSynchronization.run(budget: .milliseconds(20)) {
                do { try await Task.sleep(for: .seconds(60)) } catch {
                    await state.append("cancelled")
                    throw error
                }
            }
        }
        #expect(await state.events == ["cancelled"])
    }

    @Test func `fast synchronization does not wait for the budget`() async throws {
        try await WidgetSynchronization.run(budget: .seconds(60)) {}
    }
}

private actor CompletionEvents: TaskBulkUpdateRepositoryProtocol {
    private(set) var events: [String] = []
    private(set) var isDone = false
    let reject: Bool
    init(reject: Bool = false) {
        self.reject = reject
    }

    func append(_ event: String) {
        events.append(event)
    }

    func apply(_ change: TaskBulkChange, toTaskIDs ids: [EntityID]) throws -> [VikunjaTask] {
        if reject {
            throw VikunjaError.notFound
        }
        guard case let .completion(value) = change else { Issue.record("Expected completion"); return [] }
        isDone = value
        events.append("save:\(ids.first?.remoteValue ?? -1):\(value)")
        return []
    }
}
