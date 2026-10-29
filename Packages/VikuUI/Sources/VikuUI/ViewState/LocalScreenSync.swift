import Foundation
import Observation
import VikunjaCore

/// Shared lifecycle for local-first screens. Own no detached UI tasks: views
/// run these methods in `.task`, so observation ends when the view disappears.
@MainActor
@Observable
public final class LocalScreenSync {
    public private(set) var isPreparingInitialSnapshot = false
    public private(set) var initialFailureMessage: String?
    private let trigger: SyncTriggering
    private let localData: LocalDataObserving
    private let toastPresenter: ToastPresenting

    public init(trigger: SyncTriggering, localData: LocalDataObserving, toastPresenter: ToastPresenting) {
        self.trigger = trigger
        self.localData = localData
        self.toastPresenter = toastPresenter
    }

    public func hasInitialSnapshot() async throws -> Bool {
        try await trigger.hasInitialSnapshot()
    }

    public func start(
        scope: SyncScope = .account,
        reload: () async -> Void,
        onInitialFailure: (String) -> Void,
    ) async {
        defer { isPreparingInitialSnapshot = false }
        do {
            isPreparingInitialSnapshot = try await !hasInitialSnapshot()
            await reload()
            // Comment threads are demand-loaded explicitly, never by a query.
            if case let .task(id) = scope {
                let initialScope: SyncScope = isPreparingInitialSnapshot ? .task(id) : .comments(id)
                try await trigger.refresh(scope: initialScope)
            } else {
                try await trigger.prepare()
            }
            guard !Task.isCancelled else { return }
            isPreparingInitialSnapshot = false
            initialFailureMessage = nil
            await reload()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            let message = message(for: error)
            if isPreparingInitialSnapshot {
                initialFailureMessage = message
                onInitialFailure(message)
            } else {
                toastPresenter.show(message, style: .error)
            }
        }
    }

    public func observe(reload: () async -> Void) async {
        do {
            for try await _ in await localData.localChanges() {
                guard !Task.isCancelled else { return }
                await reload()
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            toastPresenter.show(message(for: error), style: .error)
        }
    }

    public func refresh(scope: SyncScope = .account, reload: () async -> Void) async {
        do {
            try await trigger.refresh(scope: scope)
            initialFailureMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            toastPresenter.show(message(for: error), style: .error)
        }
        guard !Task.isCancelled else { return }
        await reload()
    }

    private func message(for error: any Error) -> String {
        (error as? VikunjaError)?.displayMessage ?? error.localizedDescription
    }
}
