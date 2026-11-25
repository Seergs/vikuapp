import SwiftUI
import VikunjaCore

public struct PriorityOption: Identifiable, Sendable {
    public let priority: VikunjaTask.Priority
    public let label: String
    public let color: Color

    public var id: VikunjaTask.Priority {
        priority
    }

    /// Priorities with distinct colors for task title shortcuts.
    public static let all: [PriorityOption] = [
        PriorityOption(
            priority: .low,
            label: String(localized: "Low", bundle: .module),
            color: VikuColor.Priority.low,
        ),
        PriorityOption(
            priority: .medium,
            label: String(localized: "Medium", bundle: .module),
            color: VikuColor.Priority.medium,
        ),
        PriorityOption(
            priority: .high,
            label: String(localized: "High", bundle: .module),
            color: VikuColor.Priority.high,
        ),
        PriorityOption(
            priority: .urgent,
            label: String(localized: "Urgent", bundle: .module),
            color: VikuColor.Priority.urgent,
        ),
    ]
}

/// Same tinted-card language as `TaskDetailView`'s `BlockedBanner` — a red
/// card rather than plain inline text, so a save failure reads as clearly as
/// every other error state in the app.
public struct SaveErrorBanner: View {
    let message: String

    @Environment(\.vikuPalette) private var palette

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .center, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(palette.semanticDangerText)
            Text(verbatim: message)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(palette.semanticDangerText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.semanticDanger.opacity(0.12),
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}
