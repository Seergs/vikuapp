import Foundation
@testable import Settings
import Testing
import VikunjaCore

private final class FakePendingSyncOperationsProvider: PendingSyncOperationsProviding, @unchecked Sendable {
    var snapshots: [[PendingSyncOperation]] = []
    var error: Error?
    #if DEBUG
    var clearError: Error?
    private(set) var clearedAccountIDs: [UUID] = []

    func clearPendingSyncQueue(accountID: UUID) async throws {
        clearedAccountIDs.append(accountID)
        if let clearError {
            throw clearError
        }
    }
    #endif

    var discardError: Error?
    private(set) var discardedIDs: [(id: Int64, accountID: UUID)] = []

    func observePendingSyncOperations(
        accountID _: UUID,
    ) async -> AsyncThrowingStream<[PendingSyncOperation], Error> {
        let snapshots = snapshots
        let error = error
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }

    func discardConflictedPendingSyncOperation(id: Int64, accountID: UUID) async throws {
        discardedIDs.append((id, accountID))
        if let discardError {
            throw discardError
        }
    }
}

@MainActor
struct PendingSyncViewModelTests {
    private func operation(
        id: Int64 = 1,
        title: String = "Task",
        createdAt: Date = Date(),
        needsConflictResolution: Bool = false,
        status: SyncItemStatus = .pending,
    ) -> PendingSyncOperation {
        PendingSyncOperation(
            id: id,
            entity: .task,
            action: .update,
            targetTitle: title,
            createdAt: createdAt,
            status: status,
            needsConflictResolution: needsConflictResolution,
        )
    }

    #if DEBUG
    @Test
    func `clearing the queue targets the active account and reports success`() async {
        let provider = FakePendingSyncOperationsProvider()
        let toast = FakeToastPresenter()
        let accountID = UUID()
        let viewModel = PendingSyncViewModel(provider: provider, accountID: accountID, toastPresenter: toast)

        await viewModel.clearQueue()

        #expect(provider.clearedAccountIDs == [accountID])
        #expect(toast.shownMessages.contains { $0.style == .success })
        #expect(!viewModel.isClearingQueue)
    }

    @Test
    func `a queue clear failure reports an error and allows retry`() async {
        let provider = FakePendingSyncOperationsProvider()
        provider.clearError = VikunjaError.network("offline")
        let toast = FakeToastPresenter()
        let viewModel = PendingSyncViewModel(provider: provider, accountID: UUID(), toastPresenter: toast)

        await viewModel.clearQueue()

        #expect(toast.shownMessages.contains { $0.style == .error })
        #expect(!viewModel.isClearingQueue)
        provider.clearError = nil
        await viewModel.clearQueue()
        #expect(provider.clearedAccountIDs.count == 2)
        #expect(toast.shownMessages.last?.style == .success)
    }
    #endif

    @Test
    func `the real queue drains without waiting for presentation`() async {
        let provider = FakePendingSyncOperationsProvider()
        let entries = (1 ... 10).map { operation(id: Int64($0)) }
        provider.snapshots = [entries, []]
        let viewModel = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: FakeToastPresenter(),
        )

        await viewModel.observe()

        #expect(viewModel.operations.isEmpty)
        #expect(viewModel.presentation.operations == entries)
        #expect(viewModel.presentation.nextUpdate != nil)
        #expect(viewModel.loadState == .loaded)
    }

    @Test
    func `cancelling a scheduled animation preserves rows until observation restarts`() async {
        let provider = FakePendingSyncOperationsProvider()
        let entry = operation()
        provider.snapshots = [[entry], []]
        let viewModel = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: FakeToastPresenter(),
        )
        await viewModel.observe()
        let animation = Task { await viewModel.advancePresentation() }
        animation.cancel()
        await animation.value

        #expect(viewModel.presentation.operations == [entry])
        provider.snapshots = [[]]
        await viewModel.observe()
        #expect(viewModel.presentation.operations.isEmpty)
        #expect(viewModel.presentation.nextUpdate == nil)
    }

    @Test
    func `loads the latest snapshot`() async {
        let provider = FakePendingSyncOperationsProvider()
        let entry = operation()
        provider.snapshots = [
            [],
            [entry],
        ]
        let viewModel = PendingSyncViewModel(
            provider: provider,
            accountID: UUID(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.observe()

        #expect(viewModel.operations == [entry])
        #expect(viewModel.loadState == .loaded)
    }

    @Test
    func `an empty queue reports loaded`() async {
        let viewModel = PendingSyncViewModel(
            provider: FakePendingSyncOperationsProvider(),
            accountID: UUID(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.observe()

        #expect(viewModel.operations.isEmpty)
        #expect(viewModel.loadState == .loaded)
    }

    @Test
    func `a stream error surfaces as a failure`() async {
        let provider = FakePendingSyncOperationsProvider()
        provider.error = VikunjaError.notFound
        let viewModel = PendingSyncViewModel(
            provider: provider,
            accountID: UUID(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.observe()

        #expect(viewModel.loadState == .failure(VikunjaError.notFound.displayMessage))
    }

    @Test
    func `discarding a conflict asks the provider to remove it`() async {
        let provider = FakePendingSyncOperationsProvider()
        let toast = FakeToastPresenter()
        let accountID = UUID()
        let viewModel = PendingSyncViewModel(
            provider: provider,
            accountID: accountID,
            toastPresenter: toast,
        )
        let conflict = operation(id: 42, needsConflictResolution: true)

        await viewModel.discard(conflict)

        #expect(provider.discardedIDs.count == 1)
        #expect(provider.discardedIDs.first?.id == 42)
        #expect(provider.discardedIDs.first?.accountID == accountID)
        #expect(toast.shownMessages.contains { $0.style == .success })
    }

    @Test
    func `discarding a non conflict does nothing`() async {
        let provider = FakePendingSyncOperationsProvider()
        let viewModel = PendingSyncViewModel(
            provider: provider,
            accountID: UUID(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.discard(operation())

        #expect(provider.discardedIDs.isEmpty)
    }

    @Test
    func `unconfirmed creation cannot be discarded as an ordinary conflict`() async {
        let provider = FakePendingSyncOperationsProvider()
        let viewModel = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: FakeToastPresenter(),
        )
        let review = PendingSyncOperation(
            id: 42,
            entity: .task,
            action: .create,
            targetTitle: "Review",
            createdAt: Date(),
            status: .failed,
            needsConflictResolution: true,
            failureMessage: "Check server",
        )
        await viewModel.discard(review)
        #expect(provider.discardedIDs.isEmpty)
    }

    @Test
    func `a discard failure surfaces an error toast`() async {
        let provider = FakePendingSyncOperationsProvider()
        provider.discardError = VikunjaError.network("offline")
        let toast = FakeToastPresenter()
        let viewModel = PendingSyncViewModel(
            provider: provider,
            accountID: UUID(),
            toastPresenter: toast,
        )

        await viewModel.discard(operation(needsConflictResolution: true))

        #expect(toast.shownMessages.contains { $0.style == .error })
    }
}

@MainActor
private final class FakeAccountReloader: AccountReloading {
    var error: Error?
    var onReload: (() async -> Void)?
    private(set) var calls = 0

    func reloadFromServer() async throws {
        calls += 1
        await onReload?()
        if let error {
            throw error
        }
    }
}

extension PendingSyncViewModelTests {
    @Test func `server reload is available for failures and conflicts with an injected reloader`() async {
        let provider = FakePendingSyncOperationsProvider()
        provider.snapshots = [[operation()]]
        let model = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: FakeToastPresenter(),
            accountReloader: FakeAccountReloader(),
        )
        await model.observe()
        #expect(!model.canReloadFromServer)
        provider.snapshots = [[operation(status: .failed)]]
        await model.observe()
        #expect(model.canReloadFromServer)
        provider.snapshots = [[operation(needsConflictResolution: true)]]
        await model.observe()
        #expect(model.canReloadFromServer)
    }

    @Test func `reload reports success only after completion and ignores overlapping attempts`() async {
        let provider = FakePendingSyncOperationsProvider()
        provider.snapshots = [[operation(status: .failed)]]
        let toast = FakeToastPresenter()
        let reloader = FakeAccountReloader()
        let model = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: toast, accountReloader: reloader,
        )
        await model.observe()
        reloader.onReload = {
            #expect(model.isReloading)
            #expect(toast.shownMessages.isEmpty)
            await model.reloadFromServer()
        }
        await model.reloadFromServer()
        #expect(reloader.calls == 1)
        #expect(model.operations.isEmpty)
        #expect(model.presentation.operations.isEmpty)
        #expect(!model.isReloading)
        #expect(toast.shownMessages.last?.style == .success)
    }

    @Test func `failed reload keeps the visible queue and allows retry while cancellation stays silent`() async {
        let provider = FakePendingSyncOperationsProvider()
        let failed = operation(status: .failed)
        provider.snapshots = [[failed]]
        let toast = FakeToastPresenter()
        let reloader = FakeAccountReloader()
        let model = PendingSyncViewModel(
            provider: provider, accountID: UUID(), toastPresenter: toast, accountReloader: reloader,
        )
        await model.observe()
        reloader.error = VikunjaError.timeout
        await model.reloadFromServer()
        #expect(model.operations == [failed])
        #expect(model.presentation.operations == [failed])
        #expect(!model.isReloading)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.last?.style == .error)
        reloader.error = CancellationError()
        await model.reloadFromServer()
        #expect(toast.shownMessages.count == 1)
        reloader.error = nil
        await model.reloadFromServer()
        #expect(reloader.calls == 3)
        #expect(toast.shownMessages.last?.style == .success)
    }
}
