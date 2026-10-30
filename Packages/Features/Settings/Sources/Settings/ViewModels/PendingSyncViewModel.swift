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

    private let provider: PendingSyncOperationsProviding
    private let accountID: UUID
    private let toastPresenter: ToastPresenting

    public init(
        provider: PendingSyncOperationsProviding,
        accountID: UUID,
        toastPresenter: ToastPresenting,
    ) {
        self.provider = provider
        self.accountID = accountID
        self.toastPresenter = toastPresenter
    }

    /// Consumes the live stream until the calling `.task` is cancelled.
    public func observe() async {
        if operations.isEmpty {
            loadState = .loading
        }

        let updates = await provider.observePendingSyncOperations(accountID: accountID)
        var isInitialSnapshot = true
        do {
            for try await operations in updates {
                guard !Task.isCancelled else { return }
                self.operations = operations
                presentation.receive(operations, reset: isInitialSnapshot)
                isInitialSnapshot = false
                loadState = .loaded
            }
            guard !Task.isCancelled else { return }
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
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

    /// Conflict items can never drain, so removing one is only queue cleanup.
    /// The live observation removes the row from the list once it's gone.
    public func discard(_ operation: PendingSyncOperation) async {
        guard operation.needsConflictResolution, operation.failureMessage == nil else { return }

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
