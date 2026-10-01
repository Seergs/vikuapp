import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// One bucket's column: a header (title, task count, add-task button), a
/// vertically scrolling run of draggable cards, and a native
/// `.dropDestination` that accepts a card dragged from any other column.
///
/// Deliberately does not special-case the done bucket — the server/view-model
/// already handle the completion flip on a successful move (see
/// `KanbanBoardViewModel.moveTask(_:to:)`), so this column looks exactly like
/// any other one.
struct KanbanColumnView: View {
    private static let width: CGFloat = 300

    let bucket: KanbanBucket
    let onSelectTask: (VikunjaTask) -> Void
    let onToggleDone: (VikunjaTask) -> Void
    /// The dropped card's task id. Resolving it to a full `VikunjaTask`
    /// needs every bucket's tasks, not just this column's own, so the lookup
    /// (and the `moveTask` call) happens in `KanbanBoardView`.
    let onDropTaskID: (Int) -> Void
    let onAddTask: (String) -> Void

    @State private var isTargeted = false
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            header
                .padding(.top, VikuSpacing.sm)

            ScrollView {
                LazyVStack(spacing: VikuSpacing.sm) {
                    ForEach(bucket.tasks) { task in
                        card(for: task)
                    }
                }
                .padding(.top, VikuSpacing.sm)
            }

            if isAddingTask {
                addTaskField
            }
        }
        .padding(VikuSpacing.sm)
        .frame(width: Self.width)
        .background(isTargeted ? VikuColor.brandPrimary.opacity(0.08) : VikuColor.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let taskID = Int(idString) else { return false }
            onDropTaskID(taskID)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var header: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(verbatim: bucket.title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(verbatim: "\(bucket.tasks.count)")
                .font(VikuFont.caption)
                .foregroundStyle(VikuColor.textSecondary)
                .padding(.horizontal, VikuSpacing.xs + VikuSpacing.xxs)
                .background(VikuColor.Surface.field, in: Capsule())

            Spacer(minLength: VikuSpacing.xs)

            Button {
                isAddingTask = true
                isNewTaskFieldFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, VikuSpacing.xs)
    }

    private func card(for task: VikunjaTask) -> some View {
        VikuTaskRow(
            task: task,
            project: nil,
            showsProjectBadge: false,
            // Labels sit next to the due date instead of wrapping onto their
            // own line below — the narrow column has no room to spare for a
            // separate label row.
            inlineLabels: true,
            onToggle: { onToggleDone(task) },
            onOpen: { onSelectTask(task) },
            contextMenu: { EmptyView() },
        )
        .padding(VikuSpacing.sm)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        .draggable(String(task.id))
    }

    private var addTaskField: some View {
        HStack(spacing: VikuSpacing.xs) {
            TextField("New task", text: $newTaskTitle)
                .font(VikuFont.footnote)
                .focused($isNewTaskFieldFocused)
                .onSubmit(submitNewTask)

            Button("Add", action: submitNewTask)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                isAddingTask = false
                newTaskTitle = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(VikuSpacing.sm)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
    }

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAddTask(title)
        newTaskTitle = ""
        isNewTaskFieldFocused = true
    }
}
