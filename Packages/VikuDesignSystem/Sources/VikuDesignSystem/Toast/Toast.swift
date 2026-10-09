import Foundation
import VikunjaCore

/// One queued or currently-presented toast. `duration` is fixed per style
/// rather than configurable per call site — errors linger a bit longer than
/// success/info — which keeps every call to `ToastPresenting.show` a
/// one-liner.
public struct Toast: Identifiable, Equatable {
    public let id = UUID()
    public let message: String
    public let style: ToastStyle
    /// What tapping this toast does, if anything. `nil` for a plain,
    /// dismiss-only toast.
    public let action: ToastAction?

    var duration: TimeInterval {
        style == .error ? 4 : 2.5
    }
}
