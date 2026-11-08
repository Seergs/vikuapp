/// Presentation only: saving starts immediately. A slow save shows its spinner
/// after one second and keeps it visible for at least one second before closing.
struct QuickAddSavingPresentation {
    private(set) var isVisible = false
    private var startedAt: Duration?
    private var shownAt: Duration?

    mutating func update(isSaving: Bool, at now: Duration) -> Duration? {
        if isSaving {
            if startedAt == nil {
                startedAt = now
            }
            guard !isVisible else { return nil }
            let remaining = .seconds(1) - (now - (startedAt ?? now))
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
