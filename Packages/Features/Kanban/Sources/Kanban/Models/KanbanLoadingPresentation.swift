import Foundation

/// Presentation timing only; repository and sync operations never wait for this state.
struct KanbanLoadingPresentation {
    private(set) var isVisible = false
    private var startedAt: Duration?
    private var shownAt: Duration?

    /// Returns the time until presentation needs another update, if any.
    mutating func update(isLoading: Bool, at now: Duration) -> Duration? {
        if isLoading {
            if startedAt == nil {
                startedAt = now
            }
            if isVisible {
                return nil
            }
            let remaining = .milliseconds(500) - (now - (startedAt ?? now))
            if remaining > .zero {
                return remaining
            }
            isVisible = true
            shownAt = now
        } else {
            if let shownAt {
                let remaining = .seconds(1) - (now - shownAt)
                if remaining > .zero {
                    return remaining
                }
            }
            self = Self()
        }
        return nil
    }
}
