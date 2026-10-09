import SwiftUI

private struct ToastHostModifier: ViewModifier {
    let center: ToastCenter

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = center.current {
                    ToastView(toast: toast)
                        .padding(.horizontal, VikuSpacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { center.handleTap() }
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .animation(.spring(duration: 0.35), value: center.current)
    }
}

public extension View {
    /// Attaches the single toast host for the whole app. Call this once, as
    /// high in the hierarchy as possible, so a toast floats above every
    /// screen, sheet, and the tab bar — not once per feature. Everything
    /// downstream shows a toast by taking a `ToastPresenting` dependency and
    /// calling `show(_:style:)`; it never needs to know this modifier exists.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}
