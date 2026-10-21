import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Lets the user choose which kind of relation to add — every `RelationKind`
/// except `subtask`/`parenttask`. `subtask` has its own "Add" button on the
/// task detail screen's Subtasks checklist, which skips straight to
/// `RelationTaskPickerSheet` with the kind already known; `parenttask` (the
/// inverse of `subtask`, viewed from the child) isn't creatable from either
/// side's UI yet. Driven entirely by a closure, so it lives in `VikuUI`
/// rather than `Features/Tasks` — every screen that offers "add relation"
/// can present it without importing another feature, mirroring
/// `LabelPickerSheet`.
public struct RelationKindPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vikuPalette) private var palette
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
                            .foregroundStyle(palette.brand)
                        Text(verbatim: kind.localizedDisplayName)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(Text("Relation Type", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
