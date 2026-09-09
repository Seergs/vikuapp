import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The Subtasks section: a read-only checklist of the task's subtasks. Kept
/// separate from the combined "Relations" section below because it renders as a
/// checklist, not a relation list. The caller only shows this when the task has
/// subtasks.
struct SubtasksSection: View {
    let subtasks: [TaskRelation]
    let color: Color

    var body: some View {
        SectionBlock(
            title: "Subtasks",
            count: "\(subtasks.filter(\.isDone).count)/\(subtasks.count)",
        ) {
            SubtasksCard(subtasks: subtasks, color: color)
        }
    }
}

/// Read-only for now: a `TaskRelation` is a thin summary (see its doc
/// comment), not enough to safely round-trip through
/// `TaskRepositoryProtocol.update(_:)` without first fetching the full task —
/// an extra request per row this screen doesn't make yet.
private struct SubtasksCard: View {
    let subtasks: [TaskRelation]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                if index > 0 {
                    Divider().padding(.leading, VikuSpacing.md - VikuSpacing.xxs)
                }
                HStack(spacing: VikuSpacing.sm) {
                    TaskDetailCheckbox(isDone: subtask.isDone, color: color, size: 20)
                    Text(subtask.title)
                        .font(VikuFont.subheadline)
                        .foregroundStyle(subtask.isDone ? VikuColor.textTertiary : Color.primary)
                        .strikethrough(subtask.isDone)
                    Spacer()
                }
                .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            }
        }
        .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }
}
