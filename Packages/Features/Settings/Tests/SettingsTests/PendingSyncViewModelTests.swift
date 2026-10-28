import Foundation
@testable import Settings
import Testing
import VikunjaCore

private final class FakePendingSyncOperationsProvider: PendingSyncOperationsProviding, @unchecked Sendable {
    var snapshots: [[PendingSyncOperation]] = []
    var error: Error?
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
    ) -> PendingSyncOperation {
        PendingSyncOperation(
            id: id,
            entity: .task,
            action: .update,
            targetTitle: title,
            createdAt: createdAt,
            status: .pending,
            needsConflictResolution: needsConflictResolution,
        )
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
