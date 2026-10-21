import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The Subtasks section: a checklist of the task's subtasks. Kept separate
/// from the combined "Relations" section below because it renders as a
/// checklist, not a relation list, and because `subtask` has its own add
/// entry point here rather than going through the generic
/// `RelationKindPickerSheet` (see that type's doc comment). Always shown
/// (even with no subtasks yet) so the "Add" button is reachable.
struct SubtasksSection: View {
    let subtasks: [TaskRelation]
    let color: Color
    let onAdd: () -> Void
    let onTap: (TaskRelation) -> Void
    let onRemove: (TaskRelation) -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        SectionBlock(
            title: String(localized: "Subtasks", bundle: .module),
            count: subtasks.isEmpty ? nil : "\(subtasks.filter(\.isDone).count)/\(subtasks.count)",
            trailing: AnyView(SectionHeaderButton(
                title: String(localized: "Add", bundle: .module),
                action: onAdd,
            )),
        ) {
            if subtasks.isEmpty {
                Text("No subtasks yet.", bundle: .module)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(palette.textTertiary)
            } else {
                SubtasksCard(subtasks: subtasks, color: color, onTap: onTap, onRemove: onRemove)
            }
        }
    }
}

/// The checkbox itself stays read-only: a `TaskRelation` is a thin summary
/// (see its doc comment), not enough to safely round-trip through
/// `TaskRepositoryProtocol.update(_:)` without first fetching the full task —
/// an extra request per row this screen doesn't make yet. Tapping the row
/// (title) navigates via `onTap`, and the trailing button removes the
/// relation via `onRemove`, mirroring `RelationsSection`'s `DependencyRow`.
private struct SubtasksCard: View {
    let subtasks: [TaskRelation]
    let color: Color
    let onTap: (TaskRelation) -> Void
    let onRemove: (TaskRelation) -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                if index > 0 {
                    Divider().padding(.leading, VikuSpacing.md - VikuSpacing.xxs)
                }
                HStack(spacing: VikuSpacing.sm) {
                    Button {
                        onTap(subtask)
                    } label: {
                        HStack(spacing: VikuSpacing.sm) {
                            TaskDetailCheckbox(isDone: subtask.isDone, color: color, size: 20)
                            Text(verbatim: subtask.title)
                                .font(VikuFont.subheadline)
                                .foregroundStyle(subtask.isDone ? palette.textTertiary : Color.primary)
                                .strikethrough(subtask.isDone)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onRemove(subtask)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(palette.fieldBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            }
        }
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }
}
