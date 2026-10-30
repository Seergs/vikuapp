import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

private struct FailingSyncTrigger: SyncTriggering {
    var hasSnapshot = true
    var error: VikunjaError = .offline

    func hasInitialSnapshot() async throws -> Bool {
        hasSnapshot
    }

    func prepare() async throws {
        throw error
    }

    func refresh(scope: SyncScope) async throws {
        throw error
    }
}

private struct NoLocalChanges: LocalDataObserving {
    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
struct LocalScreenSyncTests {
    @Test
    func `opening cached task offline reads local data without a toast`() async {
        let toast = FakeToastPresenter()
        let sync = LocalScreenSync(trigger: FailingSyncTrigger(), localData: NoLocalChanges(), toastPresenter: toast)
        var reloadCount = 0
        var failures: [String] = []

        await sync.start(
            scope: .task(.remote(1)), reload: { reloadCount += 1 }, onInitialFailure: { failures.append($0) },
        )

        #expect(reloadCount == 1)
        #expect(toast.shownMessages.isEmpty)
        #expect(failures.isEmpty)
        #expect(sync.initialFailureMessage == nil)
        #expect(!sync.isPreparingInitialSnapshot)
    }

    @Test
    func `explicit offline refresh reports one informational notice and reloads local data`() async {
        let toast = FakeToastPresenter()
        let sync = LocalScreenSync(trigger: FailingSyncTrigger(), localData: NoLocalChanges(), toastPresenter: toast)
        var reloadCount = 0

        let canLoadOnlineResources = await sync.refresh(scope: .task(.remote(1)), reload: { reloadCount += 1 })

        #expect(!canLoadOnlineResources)
        #expect(reloadCount == 1)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.first?.message == VikunjaError.offline.displayMessage)
        #expect(toast.shownMessages.first?.style == .info)
    }

    @Test
    func `offline opening without an initial snapshot still explains the failure`() async {
        let toast = FakeToastPresenter()
        let sync = LocalScreenSync(
            trigger: FailingSyncTrigger(hasSnapshot: false), localData: NoLocalChanges(), toastPresenter: toast,
        )
        var failures: [String] = []

        await sync.start(reload: {}, onInitialFailure: { failures.append($0) })

        #expect(failures == [VikunjaError.offline.displayMessage])
        #expect(sync.initialFailureMessage == VikunjaError.offline.displayMessage)
    }

    @Test
    func `automatic refresh still reports server rejection`() async {
        let toast = FakeToastPresenter()
        let sync = LocalScreenSync(
            trigger: FailingSyncTrigger(error: .unauthorized), localData: NoLocalChanges(), toastPresenter: toast,
        )

        await sync.start(scope: .task(.remote(1)), reload: {}, onInitialFailure: { _ in })

        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.first?.message == VikunjaError.unauthorized.displayMessage)
        #expect(toast.shownMessages.first?.style == .error)
    }
}
