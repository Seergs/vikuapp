import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Pending Sync" screen: a live list of the account's queued
/// mutations. The provider's stream emits an initial snapshot and again on
/// every queue change, so the list empties itself as the queue drains.
@MainActor
@Observable
public final class PendingSyncViewModel {
    public private(set) var operations: [PendingSyncOperation] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle

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
        do {
            for try await operations in updates {
                guard !Task.isCancelled else { return }
                self.operations = operations
                loadState = .loaded
            }
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Conflict items can never drain, so removing one is only queue cleanup.
    /// The live observation removes the row from the list once it's gone.
    public func discard(_ operation: PendingSyncOperation) async {
        guard operation.needsConflictResolution else { return }

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
