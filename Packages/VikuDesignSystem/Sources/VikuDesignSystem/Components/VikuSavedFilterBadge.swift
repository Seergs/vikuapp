import SwiftUI

/// The small pill shown above a saved filter's title, flagging it as a
/// filter rather than a real project. Fixed blue regardless of the active
/// `vikuPalette` - unlike `brand`-tinted chips elsewhere, this marks the
/// project's *kind*, not something that should restyle per theme.
public struct VikuSavedFilterBadge: View {
    private static let tint = Color(hex: 0x0A5FD6)

    public init() {}

    public var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            // "funnel"/"funnel.fill" aren't in this SDK's symbol catalog
            // (render as nothing, no error) - this is the same saved-filter
            // icon `HomeSelectionPickerSheet` already uses.
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Self.tint)
            Text("Saved Filter", bundle: .module)
                .foregroundStyle(.primary)
        }
        .font(.caption2)
        .fontWeight(.bold)
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.vertical, VikuSpacing.xs)
        .background(Capsule().fill(Self.tint.opacity(0.16)))
    }
}
