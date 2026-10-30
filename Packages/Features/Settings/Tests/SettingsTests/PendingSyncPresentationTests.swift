import Foundation
@testable import Settings
import Testing
import VikunjaCore

struct PendingSyncPresentationTests {
    private func operation(id: Int64, failed: Bool = false) -> PendingSyncOperation {
        PendingSyncOperation(
            id: id,
            entity: .task,
            action: .update,
            targetTitle: "Task \(id)",
            createdAt: .distantPast,
            status: failed ? .failed : .pending,
            needsConflictResolution: failed,
        )
    }

    @Test
    func `ten operations draining instantly remain visible for six seconds`() {
        let now = ContinuousClock.now
        let entries = (1 ... 10).map { operation(id: Int64($0)) }
        var presentation = PendingSyncPresentation()
        presentation.receive(entries, at: now, reset: true)
        presentation.receive([], at: now)

        presentation.advance(at: now.advanced(by: .milliseconds(599)))
        #expect(presentation.operations == entries)
        for index in 1 ... 10 {
            presentation.advance(at: now.advanced(by: .milliseconds(index * 600)))
            #expect(presentation.operations == Array(entries.dropFirst(index)))
        }
        #expect(presentation.nextUpdate == nil)
    }

    @Test
    func `rapid additions are retained even when gone before the next animation`() {
        let now = ContinuousClock.now
        let first = operation(id: 1)
        let second = operation(id: 2)
        var presentation = PendingSyncPresentation()
        presentation.receive([first], at: now)
        presentation.receive([second], at: now.advanced(by: .milliseconds(100)))
        presentation.receive([], at: now.advanced(by: .milliseconds(200)))

        #expect(presentation.operations == [first, second])
        presentation.advance(at: now.advanced(by: .milliseconds(700)))
        #expect(presentation.operations == [second])
        presentation.advance(at: now.advanced(by: .milliseconds(800)))
        #expect(presentation.operations == [second])
        presentation.advance(at: now.advanced(by: .milliseconds(1300)))
        #expect(presentation.operations.isEmpty)
    }

    @Test
    func `a retry cancels departure and shows failure information immediately`() {
        let now = ContinuousClock.now
        let failed = operation(id: 1, failed: true)
        var presentation = PendingSyncPresentation()
        presentation.receive([operation(id: 1)], at: now)
        presentation.receive([], at: now)
        presentation.receive([failed], at: now.advanced(by: .milliseconds(300)))

        #expect(presentation.operations == [failed])
        #expect(presentation.nextUpdate == nil)
        presentation.advance(at: now.advanced(by: .seconds(2)))
        #expect(presentation.operations == [failed])
    }

    @Test
    func `slow updates leave failed and waiting rows visible while other rows drain`() {
        let now = ContinuousClock.now
        let failed = operation(id: 2, failed: true)
        let waiting = operation(id: 3)
        var presentation = PendingSyncPresentation()
        presentation.receive([operation(id: 1), failed, waiting], at: now)
        presentation.receive([failed, waiting], at: now.advanced(by: .seconds(5)))
        presentation.advance(at: now.advanced(by: .milliseconds(5600)))

        #expect(presentation.operations == [failed, waiting])
        #expect(presentation.nextUpdate == nil)
        presentation.receive([failed], at: now.advanced(by: .seconds(12)))
        presentation.advance(at: now.advanced(by: .milliseconds(12600)))
        #expect(presentation.operations == [failed])
    }

    @Test
    func `resuming after a long suspension never removes multiple rows at once`() {
        let now = ContinuousClock.now
        var presentation = PendingSyncPresentation()
        presentation.receive([operation(id: 1), operation(id: 2)], at: now)
        presentation.receive([], at: now)
        presentation.advance(at: now.advanced(by: .seconds(10)))
        presentation.advance(at: now.advanced(by: .seconds(10)))

        #expect(presentation.operations.map(\.id) == [2])
        #expect(presentation.nextUpdate == now.advanced(by: .milliseconds(10600)))
    }

    @Test
    func `reopening uses the current snapshot instead of replaying old departures`() {
        let now = ContinuousClock.now
        var presentation = PendingSyncPresentation()
        presentation.receive([operation(id: 1)], at: now)
        presentation.receive([], at: now)
        presentation.receive([operation(id: 2)], at: now, reset: true)

        #expect(presentation.operations.map(\.id) == [2])
        #expect(presentation.nextUpdate == nil)
    }
}
