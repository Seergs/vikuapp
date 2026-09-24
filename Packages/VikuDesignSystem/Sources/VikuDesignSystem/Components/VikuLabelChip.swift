import SwiftUI
import VikunjaCore

/// The colored pill shown wherever a task's label appears (list rows, task
/// detail): title tinted and softly backed by the label's color, muted via
/// `Color.init?(vikuMutedHex:)` rather than the raw backend hex, so an
/// arbitrary saturation from Vikunja's own web client doesn't read as a
/// saturated block. One shared component so every screen renders labels
/// identically (previously duplicated between `VikuTaskRow` and
/// `Features/Tasks`' task detail sections).
public struct VikuLabelChip: View {
    let label: VikunjaCore.Label

    public init(label: VikunjaCore.Label) {
        self.label = label
    }

    private var color: Color {
        Color(vikuMutedHex: label.hexColor) ?? VikuColor.textSecondary
    }

    public var body: some View {
        Text(label.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xxs)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
