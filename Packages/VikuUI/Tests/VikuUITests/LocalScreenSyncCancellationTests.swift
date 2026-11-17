import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

private actor RecordingTrigger: SyncTriggering {
    private(set) var calls = 0
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {
        calls += 1
    }

    func refresh(scope: SyncScope) async throws {
        calls += 1
    }
}

private struct NoChanges: LocalDataObserving {
    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor SyncReadGate {
    nonisolated let entered = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.continuation.yield(())
        }
    }

    func release() {
        continuation?.resume(); continuation = nil
    }
}

@MainActor struct LocalScreenSyncCancellationTests {
    @Test func `cancelling the initial local read does not start synchronization`() async {
        let trigger = RecordingTrigger()
        let toast = FakeToastPresenter()
        let sync = LocalScreenSync(trigger: trigger, localData: NoChanges(), toastPresenter: toast)
        let gate = SyncReadGate()
        let request = Task {
            await sync.start(scope: .task(1), reload: { await gate.wait() }, onInitialFailure: { _ in
                Issue.record("Cancellation must not become an initial failure")
            })
        }
        for await _ in gate.entered.stream {
            break
        }
        request.cancel()
        await gate.release()
        await request.value
        #expect(await trigger.calls == 0)
        #expect(!sync.isRefreshing)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `refresh cancelled during its local reload cannot start online attachment work`() async {
        let trigger = RecordingTrigger()
        let sync = LocalScreenSync(trigger: trigger, localData: NoChanges(), toastPresenter: FakeToastPresenter())
        let gate = SyncReadGate()
        let request = Task { await sync.refresh(scope: .task(1), reload: { await gate.wait() }) }
        for await _ in gate.entered.stream {
            break
        }
        request.cancel()
        await gate.release()
        #expect(await request.value == false)
        #expect(await trigger.calls == 1)
        #expect(!sync.isRefreshing)
    }
}
