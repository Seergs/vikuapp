/// What a ViewModel needs in order to surface a toast, without knowing
/// anything about how or where it's rendered. Implemented by
/// `VikuDesignSystem`'s `ToastCenter` and injected via `AppContainer`, the
/// same way repository protocols are — so showing a toast from a ViewModel
/// never requires importing `VikuDesignSystem` or any SwiftUI type.
@MainActor
public protocol ToastPresenting {
    func show(_ message: String, style: ToastStyle)
    /// Same as `show(_:style:)`, but the toast becomes tappable: tapping it
    /// (instead of just dismissing it) triggers `action`. The default
    /// implementation ignores `action` and forwards to `show(_:style:)`, so
    /// existing conformers need no changes; `ToastCenter` is the only type
    /// that overrides this to make the tap do something.
    func show(_ message: String, style: ToastStyle, action: ToastAction?)
}

public extension ToastPresenting {
    /// Convenience for the common case: a neutral, informational toast.
    func show(_ message: String) {
        show(message, style: .info)
    }

    func show(_ message: String, style: ToastStyle, action: ToastAction?) {
        show(message, style: style)
    }
}

/// A `ToastPresenting` that does nothing. The default for previews and tests,
/// and for a collaborator wired into a screen that surfaces no toasts of its
/// own yet (the Calendar screen's `TaskListMutator`). Parallels
/// `NoopHapticFeedback`.
public struct NoopToastPresenter: ToastPresenting {
    public init() {}
    public func show(_ message: String, style: ToastStyle) {}
}
