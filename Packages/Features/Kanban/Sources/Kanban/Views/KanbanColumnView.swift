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
    let allowsMutations: Bool
    let allowsTaskCreation: Bool
    let onRefresh: () async -> Void
    let onSelectTask: (VikunjaTask) -> Void
    let onToggleDone: (VikunjaTask) -> Void
    /// The dropped card's task id. Resolving it to a full `VikunjaTask`
    /// needs every bucket's tasks, not just this column's own, so the lookup
    /// (and the `moveTask` call) happens in `KanbanBoardView`.
    let onDropTaskID: (EntityID) -> Void
    let onAddTask: (String) -> Void

    @State private var isTargeted = false
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFieldFocused: Bool
    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            header
                .padding(.top, VikuSpacing.sm)

            cards

            if isAddingTask, allowsMutations, allowsTaskCreation {
                addTaskField
            }
        }
        .padding(VikuSpacing.sm)
        .frame(width: Self.width)
        .background(isTargeted ? palette.brand.opacity(0.08) : palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            acceptDrop(items)
        } isTargeted: { isTargeted = $0 }
    }

    @ViewBuilder
    private var cards: some View {
        if bucket.tasks.isEmpty {
            // An empty List has no native insertion target and intercepts the
            // column's outer drop area. The column-level destination handles
            // the empty body, so this surface stays visually transparent.
            Rectangle()
                .fill(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        } else {
            List {
                ForEach(bucket.tasks) { task in
                    card(for: task)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                .dropDestination(for: String.self) { (items: [String], _: Int) in
                    _ = acceptDrop(items)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .listRowSpacing(VikuSpacing.sm)
            #endif
            .refreshable { await onRefresh() }
        }
    }

    private func acceptDrop(_ items: [String]) -> Bool {
        guard allowsMutations, let value = items.first, let taskID = KanbanDragIdentity.decode(value)
        else { return false }
        onDropTaskID(taskID)
        // SwiftUI can leave a destination's targeted state active after a
        // successful drop, especially when the source and destination are in
        // nested Lists. Clear our visual state as part of accepting the drop.
        isTargeted = false
        return true
    }

    private var header: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(verbatim: bucket.title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(verbatim: bucket.limit > 0 ? "\(bucket.tasks.count)/\(bucket.limit)" : "\(bucket.tasks.count)")
                .font(VikuFont.caption)
                .foregroundStyle(bucket.isFull ? palette.semanticDangerText : palette.textSecondary)
                .padding(.horizontal, VikuSpacing.xs + VikuSpacing.xxs)
                .background(palette.fieldBackground, in: Capsule())

            Spacer(minLength: VikuSpacing.xs)

            Button {
                isAddingTask = true
                isNewTaskFieldFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(VikuFont.footnote.weight(.semibold))
                    .foregroundStyle(bucket.isFull ? palette.textTertiary : palette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!allowsMutations || !allowsTaskCreation || bucket.isFull)
            .accessibilityLabel(Text("Add task", bundle: .module))
            .accessibilityHint(bucket.isFull
                ? Text("This column is full", bundle: .module)
                : Text("Create a task in this column", bundle: .module))
        }
        .padding(.horizontal, VikuSpacing.xs)
    }

    @ViewBuilder
    private func card(for task: VikunjaTask) -> some View {
        if allowsMutations {
            cardContent(for: task)
                .draggable(KanbanDragIdentity.encode(task.id)) {
                    cardContent(for: task)
                }
        } else {
            cardContent(for: task)
        }
    }

    private func cardContent(for task: VikunjaTask) -> some View {
        VikuTaskRow(
            task: task,
            project: nil,
            showsProjectBadge: false,
            // Labels sit next to the due date instead of wrapping onto their
            // own line below — the narrow column has no room to spare for a
            // separate label row.
            inlineLabels: true,
            allowsCompletionChanges: allowsMutations,
            onToggle: { onToggleDone(task) },
            onOpen: { onSelectTask(task) },
            contextMenu: { EmptyView() },
        )
        .padding(VikuSpacing.sm)
        .background(palette.fieldBackground, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
    }

    private var addTaskField: some View {
        HStack(spacing: VikuSpacing.xs) {
            TextField(String(localized: "New task", bundle: .module), text: $newTaskTitle)
                .font(VikuFont.footnote)
                .focused($isNewTaskFieldFocused)
                .onSubmit(submitNewTask)

            Button(action: submitNewTask) { Text("Add", bundle: .module) }
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .disabled(bucket.isFull || newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                isAddingTask = false
                newTaskTitle = ""
            } label: {
                Image(systemName: "xmark")
                    .font(VikuFont.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(VikuSpacing.sm)
        .background(palette.fieldBackground, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
    }

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !bucket.isFull else { return }
        onAddTask(title)
        newTaskTitle = ""
        isNewTaskFieldFocused = true
    }
}
