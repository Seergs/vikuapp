import Foundation

/// Presentation deadlines only: completion of the underlying operation never
/// waits for the indicator's minimum visible duration.
struct NotificationProgressPresentation {
    private var isActive = false
    private var startedAt: ContinuousClock.Instant?
    private var shownAt: ContinuousClock.Instant?

    var isVisible: Bool {
        shownAt != nil
    }

    var nextUpdate: ContinuousClock.Instant? {
        if isActive, shownAt == nil {
            return startedAt?.advanced(by: .seconds(1))
        }
        if !isActive {
            return shownAt?.advanced(by: .seconds(1))
        }
        return nil
    }

    mutating func update(isActive: Bool, at now: ContinuousClock.Instant = .now) {
        if isActive, !self.isActive {
            startedAt = now
        }
        self.isActive = isActive
        advance(at: now)
    }

    mutating func advance(at now: ContinuousClock.Instant = .now) {
        if isActive, shownAt == nil, let startedAt, now >= startedAt.advanced(by: .seconds(1)) {
            shownAt = now
        } else if !isActive {
            startedAt = nil
            if let shownAt, now >= shownAt.advanced(by: .seconds(1)) {
                self.shownAt = nil
            }
        }
    }
}
