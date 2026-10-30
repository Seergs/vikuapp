import Foundation
@testable import Settings
import Testing
import VikunjaCore

private struct RecoveryOperationsProvider: PendingSyncOperationsProviding {
    let operations: [PendingSyncOperation]
    func observePendingSyncOperations(accountID: UUID) async -> AsyncThrowingStream<[PendingSyncOperation], Error> {
        AsyncThrowingStream { $0.yield(operations); $0.finish() }
    }

    func discardConflictedPendingSyncOperation(id: Int64, accountID: UUID) async throws {}
    #if DEBUG
    func clearPendingSyncQueue(accountID: UUID) async throws {}
    #endif
}

@MainActor
private final class RecoveryCommands: KanbanCreationRecovering {
    var buckets = [KanbanCreationBucket(id: 20, title: "Available", isFull: false)]
    var error: (any Error)?
    var onRetry: (() async -> Void)?
    private(set) var retries: [(Int64, Int?)] = []
    private(set) var deletions: [Int64] = []
    private(set) var bucketRequests: [Int64] = []

    func recoveryBuckets(operationID: Int64) async throws -> [KanbanCreationBucket] {
        bucketRequests.append(operationID)
        if let error {
            throw error
        }
        return buckets
    }

    func retryCreation(operationID: Int64, bucketID: Int?) async throws {
        retries.append((operationID, bucketID))
        await onRetry?()
        if let error {
            throw error
        }
    }

    func deleteRejectedCreation(operationID: Int64) async throws {
        deletions.append(operationID)
        if let error {
            throw error
        }
    }
}

@MainActor
private final class RecoveryToast: ToastPresenting {
    private(set) var messages: [String] = []
    func show(_ message: String, style: ToastStyle) {
        messages.append(message)
    }
}

@MainActor
struct KanbanCreationRecoveryTests {
    private func operation(recoverable: Bool = true) -> PendingSyncOperation {
        PendingSyncOperation(
            id: 1, entity: .task, action: .create, targetTitle: "Offline", createdAt: Date(),
            status: .failed, needsConflictResolution: true, failureMessage: "Full",
            canRecoverKanbanCreation: recoverable,
        )
    }

    @Test func `retry redirect and delete target the selected operation without a success flash`() async {
        let operation = operation()
        let commands = RecoveryCommands()
        let toast = RecoveryToast()
        let model = PendingSyncViewModel(
            provider: RecoveryOperationsProvider(operations: [operation]), accountID: UUID(),
            toastPresenter: toast, creationRecovery: commands,
        )
        await model.observe()
        await model.chooseRecoveryBucket(for: operation)
        #expect(model.recoveryOperation == operation)
        #expect(model.recoveryBuckets == commands.buckets)
        await model.retryCreation(operation)
        await model.retryCreation(operation, bucketID: 20)
        await model.deleteRejectedCreation(operation)
        #expect(commands.retries.map(\.0) == [1, 1])
        #expect(commands.retries.map(\.1) == [nil, 20])
        #expect(commands.deletions == [1])
        #expect(model.busyOperationIDs.isEmpty)
        #expect(toast.messages.isEmpty)
    }

    @Test func `unknown outcomes and departed rows cannot invoke recovery`() async {
        let operation = operation(recoverable: false)
        let commands = RecoveryCommands()
        let model = PendingSyncViewModel(
            provider: RecoveryOperationsProvider(operations: [operation]), accountID: UUID(),
            toastPresenter: RecoveryToast(), creationRecovery: commands,
        )
        await model.observe()
        await model.retryCreation(operation)
        await model.deleteRejectedCreation(operation)
        await model.chooseRecoveryBucket(for: operation)
        #expect(commands.retries.isEmpty)
        #expect(commands.deletions.isEmpty)
        #expect(commands.bucketRequests.isEmpty)
        #expect(!model.canRecover(self.operation()))
        let departed = PendingSyncViewModel(
            provider: RecoveryOperationsProvider(operations: []), accountID: UUID(),
            toastPresenter: RecoveryToast(), creationRecovery: commands,
        )
        await departed.observe()
        await departed.retryCreation(self.operation())
        #expect(commands.retries.isEmpty)
    }

    @Test func `capacity failure leaves the operation visible and shows actionable feedback`() async {
        let operation = operation()
        let commands = RecoveryCommands()
        commands.error = VikunjaError.bucketFull
        let toast = RecoveryToast()
        let model = PendingSyncViewModel(
            provider: RecoveryOperationsProvider(operations: [operation]), accountID: UUID(),
            toastPresenter: toast, creationRecovery: commands,
        )
        await model.observe()
        await model.retryCreation(operation, bucketID: 20)
        #expect(model.operations == [operation])
        #expect(model.busyOperationIDs.isEmpty)
        #expect(toast.messages == [VikunjaError.bucketFull.displayMessage])
    }

    @Test func `overlapping retry cannot submit the same operation twice`() async {
        let operation = operation()
        let commands = RecoveryCommands()
        let model = PendingSyncViewModel(
            provider: RecoveryOperationsProvider(operations: [operation]), accountID: UUID(),
            toastPresenter: RecoveryToast(), creationRecovery: commands,
        )
        await model.observe()
        commands.onRetry = { await model.retryCreation(operation) }
        await model.retryCreation(operation)
        #expect(commands.retries.count == 1)
        #expect(model.busyOperationIDs.isEmpty)
    }

    @Test func `cancelled destination lookup presents no picker or error toast`() async {
        let operation = operation()
        let commands = RecoveryCommands()
        commands.error = CancellationError()
        let toast = RecoveryToast()
        let model = PendingSyncViewModel(
            provider: RecoveryOperationsProvider(operations: [operation]), accountID: UUID(),
            toastPresenter: toast, creationRecovery: commands,
        )
        await model.observe()
        await model.chooseRecoveryBucket(for: operation)
        #expect(model.recoveryOperation == nil)
        #expect(model.busyOperationIDs.isEmpty)
        #expect(toast.messages.isEmpty)
    }
}
