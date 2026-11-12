import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Pending Sync" screen: a live list of the account's queued
/// mutations. Live snapshots stay current while a separate presentation keeps
/// departures readable when the queue drains faster than the animations.
@MainActor
@Observable
public final class PendingSyncViewModel {
    public private(set) var operations: [PendingSyncOperation] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    private(set) var presentation = PendingSyncPresentation()
    let loadingIndicator = PendingSyncLoadingIndicator()
    let reloadIndicator = PendingSyncLoadingIndicator()

    private let provider: PendingSyncOperationsProviding
    private let accountID: UUID
    private let toastPresenter: ToastPresenting
    private let accountReloader: AccountReloading?
    public private(set) var isReloading = false
    private let creationRecovery: KanbanCreationRecovering?
    public private(set) var busyOperationIDs: Set<Int64> = []
    public private(set) var recoveryBuckets: [KanbanCreationBucket] = []
    var recoveryOperation: PendingSyncOperation?

    public init(
        provider: PendingSyncOperationsProviding,
        accountID: UUID,
        toastPresenter: ToastPresenting,
        creationRecovery: KanbanCreationRecovering? = nil,
        accountReloader: AccountReloading? = nil,
    ) {
        self.provider = provider
        self.accountID = accountID
        self.toastPresenter = toastPresenter
        self.creationRecovery = creationRecovery
        self.accountReloader = accountReloader
    }

    /// Consumes the live stream until the calling `.task` is cancelled.
    public func observe() async {
        defer {
            if Task.isCancelled {
                loadingIndicator.reset()
            }
        }
        if operations.isEmpty {
            setLoadState(.loading)
        }

        let updates = await provider.observePendingSyncOperations(accountID: accountID)
        var isInitialSnapshot = true
        do {
            for try await operations in updates {
                guard !Task.isCancelled else { return }
                self.operations = operations
                presentation.receive(operations, reset: isInitialSnapshot)
                isInitialSnapshot = false
                setLoadState(.loaded)
            }
            guard !Task.isCancelled else { return }
            setLoadState(.loaded)
        } catch is CancellationError {
            loadingIndicator.reset()
            return
        } catch let error as VikunjaError {
            setLoadState(.failure(error.displayMessage))
        } catch {
            setLoadState(.failure(error.localizedDescription))
        }
    }

    /// Deliver every transition synchronously; a fast loading -> loaded change
    /// must not depend on SwiftUI rendering the intermediate state.
    private func setLoadState(_ state: ScreenLoadState<Void>) {
        loadState = state
        loadingIndicator.setLoading(state.isLoading)
    }

    /// Called by a view-owned task so leaving the screen cancels the delay.
    func advancePresentation() async {
        guard let deadline = presentation.nextUpdate else { return }
        do {
            let visibleDeadline = max(deadline, .now.advanced(by: PendingSyncPresentation.departureInterval))
            try await ContinuousClock().sleep(until: visibleDeadline)
            try Task.checkCancellation()
            presentation.advance()
        } catch {
            // The view disappeared or a newer snapshot changed the deadline.
        }
    }

    #if DEBUG
    public private(set) var isClearingQueue = false

    public func clearQueue() async {
        guard !isClearingQueue else { return }
        isClearingQueue = true
        defer { isClearingQueue = false }

        do {
            try await provider.clearPendingSyncQueue(accountID: accountID)
            toastPresenter.show(String(localized: "Sync queue cleared", bundle: .module), style: .success)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }
    #endif

    public var canReloadFromServer: Bool {
        accountReloader != nil && operations.contains { $0.status == .failed || $0.needsConflictResolution }
    }

    public func reloadFromServer() async {
        guard canReloadFromServer, !isReloading, busyOperationIDs.isEmpty, let accountReloader else { return }
        isReloading = true
        reloadIndicator.setLoading(true)
        defer {
            isReloading = false
            reloadIndicator.setLoading(false)
        }
        do {
            try await accountReloader.reloadFromServer()
            // A reset removes the whole queue at once, without the normal per-row departure delay.
            operations = []
            presentation.receive([], reset: true)
            toastPresenter.show(
                String(localized: "Local changes discarded. Data reloaded from server.", bundle: .module),
                style: .success,
            )
        } catch { showRecoveryError(error) }
    }

    public func canRecover(_ operation: PendingSyncOperation) -> Bool {
        !isReloading && creationRecovery != nil && operations.contains {
            $0.id == operation.id && $0.canRecoverKanbanCreation
        }
    }

    public func chooseRecoveryBucket(for operation: PendingSyncOperation) async {
        guard canRecover(operation), let creationRecovery,
              busyOperationIDs.insert(operation.id).inserted else { return }
        defer { busyOperationIDs.remove(operation.id) }
        do {
            recoveryBuckets = try await creationRecovery.recoveryBuckets(operationID: operation.id)
            guard !Task.isCancelled, canRecover(operation) else { return }
            recoveryOperation = operation
        } catch { showRecoveryError(error) }
    }

    public func retryCreation(_ operation: PendingSyncOperation, bucketID: Int? = nil) async {
        guard canRecover(operation), let creationRecovery,
              busyOperationIDs.insert(operation.id).inserted else { return }
        defer { busyOperationIDs.remove(operation.id) }
        do {
            try await creationRecovery.retryCreation(operationID: operation.id, bucketID: bucketID)
        } catch { showRecoveryError(error) }
    }

    public func deleteRejectedCreation(_ operation: PendingSyncOperation) async {
        guard canRecover(operation), let creationRecovery,
              busyOperationIDs.insert(operation.id).inserted else { return }
        defer { busyOperationIDs.remove(operation.id) }
        do {
            try await creationRecovery.deleteRejectedCreation(operationID: operation.id)
        } catch { showRecoveryError(error) }
    }

    private func showRecoveryError(_ error: any Error) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        toastPresenter.show((error as? VikunjaError)?.displayMessage ?? error.localizedDescription, style: .error)
    }

    /// Conflict items can never drain, so removing one is only queue cleanup.
    /// The live observation removes the row from the list once it's gone.
    public func discard(_ operation: PendingSyncOperation) async {
        guard !isReloading, operation.canDiscardConflict else { return }

        do {
            try await provider.discardConflictedPendingSyncOperation(
                id: operation.id,
                accountID: accountID,
            )
            toastPresenter.show(String(localized: "Conflict removed", bundle: .module), style: .success)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }
}
