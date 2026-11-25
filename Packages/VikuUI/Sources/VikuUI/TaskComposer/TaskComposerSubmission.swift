import Observation

/// Owns a composer submission and the lifetime of its progress indicator.
@MainActor
@Observable
public final class TaskComposerSubmission {
    private var task: Task<Void, Never>?
    private var savingPresentation = LoadingPresentation()

    public var isSubmitting: Bool {
        task != nil
    }

    public var showsProgress: Bool {
        savingPresentation.isVisible
    }

    public init() {}

    public func submit<Result>(
        operation: @escaping () async -> Result?,
        onSuccess: @escaping (Result) -> Void,
    ) {
        guard !isSubmitting else { return }
        task = Task {
            defer {
                savingPresentation = LoadingPresentation()
                task = nil
            }
            guard !Task.isCancelled else { return }
            let clock = ContinuousClock()
            savingPresentation.setLoading(true)
            let revealAt = savingPresentation.nextUpdate
            let showProgress = Task {
                if let revealAt {
                    do { try await clock.sleep(until: revealAt) } catch { return }
                }
                guard !Task.isCancelled else { return }
                savingPresentation.advance()
            }

            let result = await withTaskCancellationHandler {
                await operation()
            } onCancel: {
                showProgress.cancel()
            }
            showProgress.cancel()
            guard !Task.isCancelled else { return }

            savingPresentation.setLoading(false)
            if let hideAt = savingPresentation.nextUpdate {
                do { try await clock.sleep(until: hideAt) } catch { return }
            }
            guard !Task.isCancelled, let result else { return }
            onSuccess(result)
        }
    }

    public func cancel() {
        task?.cancel()
    }
}
