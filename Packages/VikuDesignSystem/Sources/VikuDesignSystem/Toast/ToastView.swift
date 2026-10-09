import SwiftUI
import VikunjaCore

/// The pill-shaped toast surface: an icon plus message, tinted by `style`.
/// Presentation — positioning, timing, queueing — is `ToastHostModifier`'s
/// job; this view only knows how to draw one `Toast`.
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            Label {
                Text(toast.message)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
            }
            if toast.action != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, VikuSpacing.md)
        .padding(.vertical, VikuSpacing.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.3)))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(toast.action != nil ? Text("Opens the task", bundle: .module) : Text(verbatim: ""))
    }

    private var symbolName: String {
        switch toast.style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.style {
        case .success: VikuColor.Semantic.success
        case .error: VikuColor.Semantic.danger
        case .info: VikuColor.brandPrimary
        }
    }
}
