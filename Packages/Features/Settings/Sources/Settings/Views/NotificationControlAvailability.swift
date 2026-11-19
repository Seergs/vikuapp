import SwiftUI
import VikuDesignSystem

/// Disable interaction immediately while animating its visual feedback.
private struct NotificationControlAvailability: ViewModifier {
    let isDisabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .disabled(isDisabled)
            .opacity(isDisabled ? VikuOpacity.disabledControl : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isDisabled)
    }
}

extension View {
    func notificationControlsDisabled(_ isDisabled: Bool) -> some View {
        modifier(NotificationControlAvailability(isDisabled: isDisabled))
    }
}
