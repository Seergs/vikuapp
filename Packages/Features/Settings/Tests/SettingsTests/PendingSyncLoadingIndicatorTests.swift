import Foundation
@testable import Settings
import Testing
import VikunjaCore

/// Deliberately ignores task cancellation. Even a timer that resumes late must
/// not change presentation after its loading transition has become obsolete.
@MainActor
private final class IndicatorTestClock {
    private(set) var instant = ContinuousClock.now
    private(set) var sleepCount = 0
    private var sleepers: [(ContinuousClock.Instant, CheckedContinuation<Void, Never>)] = []
    private var registrations: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(until deadline: ContinuousClock.Instant) async {
        sleepCount += 1
        await withCheckedContinuation { continuation in
            if deadline <= instant {
                continuation.resume()
            } else {
                sleepers.append((deadline, continuation))
            }
            let ready = registrations.filter { $0.0 <= sleepCount }
            registrations.removeAll { $0.0 <= sleepCount }
            for (_, waiter) in ready {
                waiter.resume()
            }
        }
    }

    func waitForSleeps(_ count: Int) async {
        guard sleepCount < count else { return }
        await withCheckedContinuation { registrations.append((count, $0)) }
    }

    func advance(by duration: Duration) {
        instant = instant.advanced(by: duration)
        let ready = sleepers.filter { $0.0 <= instant }
        sleepers.removeAll { $0.0 <= instant }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    func makeIndicator() -> PendingSyncLoadingIndicator {
        PendingSyncLoadingIndicator(now: { self.instant }, sleepUntil: { await self.sleep(until: $0) })
    }
}

@MainActor
private final class ControlledLoadingQueue: PendingSyncOperationsProviding {
    private let snapshots = AsyncThrowingStream<[PendingSyncOperation], Error>.makeStream()
    private let attached = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    func observePendingSyncOperations(accountID _: UUID) async -> AsyncThrowingStream<[PendingSyncOperation], Error> {
        attached.continuation.yield(())
        return snapshots.stream
    }

    func waitUntilAttached() async {
        for await _ in attached.stream {
            return
        }
    }

    func finishEmpty() {
        snapshots.continuation.yield([])
        snapshots.continuation.finish()
    }

    func fail() {
        snapshots.continuation.finish(throwing: VikunjaError.network("Test read failure"))
    }

    func discardConflictedPendingSyncOperation(id _: Int64, accountID _: UUID) async throws {}

    #if DEBUG
    func clearPendingSyncQueue(accountID _: UUID) async throws {}
    #endif
}

@MainActor
struct PendingSyncLoadingIndicatorTests {
    @Test
    func `a fast read never shows the spinner even if the old timer resumes`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(500))
        indicator.setLoading(false)
        clock.advance(by: .milliseconds(500))
        await show?.value
        #expect(!indicator.isVisible)
    }

    @Test
    func `completion before any UI render cannot leave a spinner latched`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        indicator.setLoading(false)
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(1))
        await show?.value
        #expect(!indicator.isVisible)
    }

    @Test
    func `a read completing at 1 point 5 seconds shows the spinner from 1 to 2 seconds`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(999))
        #expect(!indicator.isVisible)
        clock.advance(by: .milliseconds(1))
        await show?.value
        #expect(indicator.isVisible)

        clock.advance(by: .milliseconds(500))
        let hide = indicator.setLoading(false)
        await clock.waitForSleeps(2)
        clock.advance(by: .milliseconds(499))
        #expect(indicator.isVisible)
        clock.advance(by: .milliseconds(1))
        await hide?.value
        #expect(!indicator.isVisible)
    }

    @Test
    func `an old show timer cannot display the spinner early for a new read`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let oldShow = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(500))
        indicator.setLoading(false)
        let newShow = indicator.setLoading(true)
        await clock.waitForSleeps(2)
        clock.advance(by: .milliseconds(500))
        await oldShow?.value
        #expect(!indicator.isVisible)
        clock.advance(by: .milliseconds(500))
        await newShow?.value
        #expect(indicator.isVisible)
        indicator.reset()
    }

    @Test
    func `a new read keeps a visible spinner without flashing or resetting its minimum duration`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(1))
        await show?.value
        let oldHide = indicator.setLoading(false)
        await clock.waitForSleeps(2)
        clock.advance(by: .milliseconds(500))
        indicator.setLoading(true)
        clock.advance(by: .milliseconds(500))
        await oldHide?.value
        #expect(indicator.isVisible)
        let hide = indicator.setLoading(false)
        await clock.waitForSleeps(3)
        await hide?.value
        #expect(!indicator.isVisible)
    }

    @Test
    func `completion after the minimum duration hides without another delay`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(1))
        await show?.value
        clock.advance(by: .seconds(4))
        let completedAt = clock.instant
        let hide = indicator.setLoading(false)
        await hide?.value
        #expect(!indicator.isVisible)
        #expect(clock.instant == completedAt)
    }

    @Test(arguments: [false, true])
    func `leaving the screen resets pending presentation and permits a clean reentry`(_ visible: Bool) async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        var obsolete = show
        if visible {
            clock.advance(by: .seconds(1))
            await show?.value
            obsolete = indicator.setLoading(false)
            await clock.waitForSleeps(2)
        }
        indicator.reset()
        #expect(!indicator.isVisible)
        clock.advance(by: .seconds(2))
        await obsolete?.value
        #expect(!indicator.isVisible)
        let nextSleep = clock.sleepCount + 1
        let freshShow = indicator.setLoading(true)
        await clock.waitForSleeps(nextSleep)
        clock.advance(by: .seconds(1))
        await freshShow?.value
        #expect(indicator.isVisible)
        indicator.reset()
    }

    @Test
    func `duplicate loading notifications do not postpone presentation`() async {
        let clock = IndicatorTestClock()
        let indicator = clock.makeIndicator()
        let show = indicator.setLoading(true)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(500))
        indicator.setLoading(true)
        clock.advance(by: .milliseconds(500))
        await show?.value
        #expect(clock.sleepCount == 1)
        #expect(indicator.isVisible)
        indicator.reset()
    }

    @Test(arguments: [false, true])
    func `the ViewModel publishes empty data or an error without waiting for presentation`(_ failed: Bool) async {
        let provider = ControlledLoadingQueue()
        let model = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: FakeToastPresenter(),
        )
        let observation = Task { await model.observe() }
        await provider.waitUntilAttached()
        #expect(model.loadState.isLoading)
        if failed {
            provider.fail()
        } else {
            provider.finishEmpty()
        }
        await observation.value
        #expect(failed ? model.loadState.failureMessage != nil : model.loadState.isLoaded)
        #expect(model.operations.isEmpty)
        #expect(!model.loadingIndicator.isVisible)
    }

    @Test
    func `cancelling the local observation resets its loading presentation`() async {
        let provider = ControlledLoadingQueue()
        let model = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: FakeToastPresenter(),
        )
        let observation = Task { await model.observe() }
        await provider.waitUntilAttached()
        observation.cancel()
        await observation.value
        #expect(!model.loadingIndicator.isVisible)
    }
}
