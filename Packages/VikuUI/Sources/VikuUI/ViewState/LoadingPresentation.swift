import Foundation

/// Presentation-only spinner timing. Operations and local persistence never
/// wait for this state: views schedule `advance` at `nextUpdate` instead.
public struct LoadingPresentation {
    public private(set) var isVisible = false
    private var isLoading = false
    private var revealAt: ContinuousClock.Instant?
    private var visibleUntil: ContinuousClock.Instant?

    public init() {}

    public var nextUpdate: ContinuousClock.Instant? {
        isLoading ? revealAt : visibleUntil
    }

    public mutating func setLoading(_ loading: Bool, now: ContinuousClock.Instant = .now) {
        if loading, !isLoading, !isVisible {
            revealAt = now.advanced(by: .seconds(1))
        }
        isLoading = loading
        if !loading {
            revealAt = nil
        }
        advance(now: now)
    }

    public mutating func advance(now: ContinuousClock.Instant = .now) {
        if isLoading, let revealAt, now >= revealAt {
            isVisible = true
            self.revealAt = nil
            visibleUntil = now.advanced(by: .seconds(1))
        }
        if !isLoading, let visibleUntil, now >= visibleUntil {
            isVisible = false
            self.visibleUntil = nil
        }
    }
}
