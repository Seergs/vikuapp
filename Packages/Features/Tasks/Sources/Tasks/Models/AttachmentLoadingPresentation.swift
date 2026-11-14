/// Presentation timing only; attachment requests and their results are never delayed.
struct AttachmentLoadingPresentation {
    private(set) var isWaiting = true
    private(set) var showsSpinner = false
    private var startedAt: Duration?
    private var shownAt: Duration?

    mutating func update(isLoading: Bool, at now: Duration) -> Duration? {
        if isLoading {
            isWaiting = true
            if startedAt == nil {
                startedAt = now
            }
            guard !showsSpinner else { return nil }
            let remaining = .milliseconds(500) - (now - (startedAt ?? now))
            if remaining > .zero {
                return remaining
            }
            showsSpinner = true
            shownAt = now
        } else {
            if let shownAt {
                let remaining = .seconds(1) - (now - shownAt)
                if remaining > .zero {
                    return remaining
                }
            }
            self = Self()
            isWaiting = false
        }
        return nil
    }
}
