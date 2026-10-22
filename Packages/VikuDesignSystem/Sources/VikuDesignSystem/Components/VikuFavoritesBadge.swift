import SwiftUI

/// The small pill shown above the Favorites pseudo-project's title, flagging
/// it as a kind rather than a real project. Fixed amber regardless of the
/// active `vikuPalette`, mirroring `VikuSavedFilterBadge`.
public struct VikuFavoritesBadge: View {
    private static let tint = VikuColor.ProjectBadge.favorite

    public init() {}

    public var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            Image(systemName: "star.fill")
                .foregroundStyle(Self.tint)
            Text("Favorites", bundle: .module)
                .foregroundStyle(.primary)
        }
        .font(.caption2)
        .fontWeight(.bold)
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.vertical, VikuSpacing.xs)
        .background(Capsule().fill(Self.tint.opacity(0.16)))
    }
}
