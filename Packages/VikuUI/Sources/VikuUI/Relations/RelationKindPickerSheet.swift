import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Lets the user choose which kind of relation to add — every `RelationKind`
/// except `subtask`/`parenttask`, which are represented on the task detail
/// screen through the (read-only, for now) Subtasks checklist instead.
/// Driven entirely by a closure, so it lives in `VikuUI` rather than
/// `Features/Tasks` — every screen that offers "add relation" can present it
/// without importing another feature, mirroring `LabelPickerSheet`.
public struct RelationKindPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (RelationKind) -> Void

    public init(onPick: @escaping (RelationKind) -> Void) {
        self.onPick = onPick
    }

    private var kinds: [RelationKind] {
        RelationKind.allCases.filter { $0 != .subtask && $0 != .parenttask }
    }

    public var body: some View {
        NavigationStack {
            List(kinds, id: \.self) { kind in
                Button {
                    onPick(kind)
                } label: {
                    HStack(spacing: VikuSpacing.sm) {
                        Image(systemName: "link")
                            .font(.system(size: 15))
                            .foregroundStyle(VikuColor.brandPrimary)
                        Text(kind.displayName)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(VikuColor.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Relation Type")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
