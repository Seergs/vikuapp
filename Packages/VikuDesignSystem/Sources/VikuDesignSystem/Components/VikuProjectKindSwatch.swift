import SwiftUI
import VikunjaCore

/// The leading icon for a pseudo-project row (Favorites, a saved filter):
/// a dashed-border square tinted per `ProjectKind`, standing in for the
/// solid color swatch a real `Project.hexColor` gets. The dashed border
/// itself is the signal that this row isn't a project with its own color —
/// it's one of Vikunja's virtual lists mixed into `/projects` (see
/// `ProjectKind`'s doc comment). Not meant for `.project`, which keeps
/// `ProjectsView`'s own hex-color swatch.
public struct VikuProjectKindSwatch: View {
    private let kind: ProjectKind

    public init(kind: ProjectKind) {
        self.kind = kind
    }

    private var tint: Color {
        VikuColor.ProjectBadge.tint(for: kind)
    }

    private var systemImage: String {
        switch kind {
        case .favorites: "star.fill"
        // No circle around it — this swatch already reads as a filter via
        // its own dashed border, so the `...circle`/`...circle.fill` variant
        // `VikuSavedFilterBadge`/`HomeSelectionPickerSheet` use would just
        // double up on that framing.
        case .savedFilter: "line.3.horizontal.decrease"
        case .project: ""
        }
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous)
            // Lighter than the icon itself — the border is just the frame,
            // the icon is what should carry the full-strength tint.
            .strokeBorder(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, dash: [1.5, 2.5]))
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)
    }
}
