import Foundation
import Testing
@testable import VikunjaPersistence

final class FakePathMonitor: PathMonitor, @unchecked Sendable {
    private var handler: (@Sendable (Bool) -> Void)?
    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0

    func setUpdateHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        self.handler = handler
    }

    func start(queue _: DispatchQueue) {
        startCallCount += 1
    }

    func cancel() {
        cancelCallCount += 1
    }

    /// Simulates `NWPathMonitor` reporting a new path status.
    func report(isSatisfied: Bool) {
        handler?(isSatisfied)
    }
}

private actor RegainedOnlyMonitor: ReachabilityMonitoring {
    private var continuation: AsyncStream<Void>.Continuation?
    private(set) var subscribedBeforeStatusRead = false
    var isReachable: Bool {
        subscribedBeforeStatusRead = continuation != nil
        return true
    }

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { continuation = $0 }
    }

    func regain() {
        continuation?.yield()
    }

    func finish() {
        continuation?.finish()
    }
}

struct ReachabilityMonitorTests {
    @Test
    func `isReachable reflects the most recent reported status`() async {
        let pathMonitor = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)

        #expect(await monitor.isReachable == false)

        pathMonitor.report(isSatisfied: true)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await monitor.isReachable == true)

        pathMonitor.report(isSatisfied: false)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await monitor.isReachable == false)
    }

    @Test
    func `reachabilityRegained fires on the first offline to online transition`() async {
        let pathMonitor = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)
        var iterator = await monitor.reachabilityRegained().makeAsyncIterator()

        pathMonitor.report(isSatisfied: false)
        pathMonitor.report(isSatisfied: true)

        await #expect(iterator.next() != nil)
    }

    @Test
    func `reachabilityRegained never fires for the initial status report`() async {
        let pathMonitor = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)
        let stream = await monitor.reachabilityRegained()

        pathMonitor.report(isSatisfied: true)

        let sawRegain = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(50))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        #expect(sawRegain == false)
    }

    @Test
    func `reachabilityRegained does not fire again while already reachable`() async {
        let pathMonitor = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)

        pathMonitor.report(isSatisfied: false)
        pathMonitor.report(isSatisfied: true)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await monitor.isReachable == true)

        // Already reachable before this subscriber even exists — a repeated
        // "satisfied" report (e.g. a path update with no actual status
        // change) is not a new transition for anyone listening.
        let stream = await monitor.reachabilityRegained()
        pathMonitor.report(isSatisfied: true)

        let sawRegain = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(50))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        #expect(sawRegain == false)
    }

    @Test
    func `every active subscriber is notified on the same transition`() async {
        let pathMonitor = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)
        var first = await monitor.reachabilityRegained().makeAsyncIterator()
        var second = await monitor.reachabilityRegained().makeAsyncIterator()

        pathMonitor.report(isSatisfied: false)
        pathMonitor.report(isSatisfied: true)

        await #expect(first.next() != nil)
        await #expect(second.next() != nil)
    }

    @Test
    func `a burst of path reports always settles on the last one`() async {
        // Each run reconnects with a quick offline/online burst. Reports that
        // reached the actor out of order used to leave some runs stuck offline.
        let runs = 300
        var stuckOffline = 0
        for _ in 0 ..< runs {
            let pathMonitor = FakePathMonitor()
            let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)
            pathMonitor.report(isSatisfied: true)
            pathMonitor.report(isSatisfied: false)
            pathMonitor.report(isSatisfied: true)
            try? await Task.sleep(for: .milliseconds(5))
            if await monitor.isReachable == false {
                stuckOffline += 1
            }
        }
        #expect(stuckOffline == 0)
    }

    @Test
    func `status updates arrive in the order they were reported`() async {
        let pathMonitor = FakePathMonitor()
        let monitor = NWPathReachabilityMonitor(pathMonitor: pathMonitor, queue: .main)
        var iterator = await monitor.reachabilityUpdates().makeAsyncIterator()
        let reports = [true, false, true, false, false, true]

        for report in reports {
            pathMonitor.report(isSatisfied: report)
        }

        var received: [Bool] = []
        for _ in reports {
            if let value = await iterator.next() {
                received.append(value)
            }
        }
        #expect(received == reports)
    }

    @Test func `the legacy status adapter subscribes first and preserves successive reconnects`() async {
        let monitor = RegainedOnlyMonitor()
        var iterator = await monitor.reachabilityUpdates().makeAsyncIterator()
        #expect(await iterator.next() == true)
        #expect(await monitor.subscribedBeforeStatusRead)
        await monitor.regain()
        #expect(await iterator.next() == false)
        #expect(await iterator.next() == true)
        await monitor.regain()
        #expect(await iterator.next() == false)
        #expect(await iterator.next() == true)
        await monitor.finish()
        #expect(await iterator.next() == nil)
    }
}
