import Observation
import VikunjaCore

/// Owns the toast queue and drives what's currently on screen. One instance
/// lives for the whole app — created once by the composition root and
/// attached via `.toastHost(_:)` as high in the view hierarchy as possible —
/// and is handed to any ViewModel that needs to surface a toast, typed as
/// `ToastPresenting` so the ViewModel never imports this package. Toasts
/// queue rather than overlap: calling `show` while one is already up waits
/// its turn instead of interrupting it.
@Observable
@MainActor
public final class ToastCenter: ToastPresenting {
    public private(set) var current: Toast?
    /// The action of a toast the user just tapped, published here for the
    /// app's navigation layer to observe and act on, then clear via
    /// `acknowledgeTappedAction()`. `ToastCenter` has no navigation
    /// knowledge of its own (see `ToastAction`'s doc comment), so it only
    /// hands this off rather than acting on it.
    public private(set) var tappedAction: ToastAction?

    private var queue: [Toast] = []
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, style: ToastStyle) {
        show(message, style: style, action: nil)
    }

    public func show(_ message: String, style: ToastStyle, action: ToastAction?) {
        queue.append(Toast(message: message, style: style, action: action))
        advanceIfNeeded()
    }

    /// Dismisses whatever's currently shown and presents the next queued
    /// toast, if any. Called by the countdown timer, and by tap-to-dismiss.
    public func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        advanceIfNeeded()
    }

    /// Called when the user taps the current toast (`ToastHostModifier`).
    /// One with no `action` just dismisses, like before; one with an action
    /// publishes it to `tappedAction` on the way out.
    public func handleTap() {
        tappedAction = current?.action
        dismissCurrent()
    }

    public func acknowledgeTappedAction() {
        tappedAction = nil
    }

    private func advanceIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.duration))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }
}
