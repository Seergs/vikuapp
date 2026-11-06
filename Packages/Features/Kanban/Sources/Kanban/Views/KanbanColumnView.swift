import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// A bucket with a single drop destination. A scroll view keeps native List
/// insertion placeholders from appearing before capacity is validated.
struct KanbanColumnView: View {
    private static let width: CGFloat = 300

    let bucket: KanbanBucket
    let searchText: String
    @Binding var dropTarget: KanbanDropTarget
    let allowsMutations: Bool
    let allowsTaskCreation: Bool
    let onRefresh: () async -> Void
    let onSelectTask: (VikunjaTask) -> Void
    let onToggleDone: (VikunjaTask) -> Void
    /// The dropped card's task id. Resolving it to a full `VikunjaTask`
    /// needs every bucket's tasks, not just this column's own, so the lookup
    /// (and the `moveTask` call) happens in `KanbanBoardView`.
    let onDropTaskID: @MainActor @Sendable (EntityID) -> Void
    let onAddTask: (String) -> Void

    private var isTargeted: Bool {
        dropTarget.bucketID == bucket.id
    }

    @State private var isAddingTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.vikuPalette) private var palette

    private var highlightColor: Color {
        bucket.isDoneBucket ? palette.semanticSuccess : palette.brand
    }

    private var content: KanbanColumnContent {
        KanbanColumnContent(bucket: bucket, searchText: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            header
                .padding(.top, VikuSpacing.sm)

            if let progress = content.capacityFraction {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(bucket.isFull ? palette.semanticDanger : palette.brand)
                    .accessibilityLabel(Text("Column capacity", bundle: .module))
                    .accessibilityValue(Text(verbatim: "\(bucket.tasks.count)/\(bucket.limit)"))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: progress)
                    .padding(.horizontal, VikuSpacing.xs)
            }

            cards

            if isAddingTask, allowsMutations, allowsTaskCreation, !bucket.isFull {
                addTaskField
            }
        }
        .padding(VikuSpacing.sm)
        .frame(width: Self.width)
        .background(isTargeted ? highlightColor.opacity(0.08) : palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: bucket.isFull)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous)
                    .strokeBorder(highlightColor, style: StrokeStyle(
                        lineWidth: 1, dash: [VikuSpacing.xs, VikuSpacing.xxs],
                    ))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: KanbanColumnDropDelegate.contentTypes, delegate: KanbanColumnDropDelegate(
            bucketID: bucket.id,
            allowsDrop: allowsMutations && !bucket.isFull,
            target: $dropTarget,
            onDropTaskID: onDropTaskID,
        ))
        .onChange(of: bucket.isFull) { _, isFull in
            guard isFull else { return }
            isAddingTask = false
            isNewTaskFieldFocused = false
            dropTarget.update(isTargeted: false, bucketID: bucket.id)
        }
    }

    @ViewBuilder
    private var cards: some View {
        if content.visibleTasks.isEmpty {
            emptyDropArea
        } else {
            ScrollView {
                LazyVStack(spacing: VikuSpacing.sm) {
                    ForEach(content.visibleTasks) { task in
                        card(for: task)
                    }
                }
            }
            .refreshable { await onRefresh() }
        }
    }

    private var emptyDropArea: some View {
        Group {
            if !bucket.tasks.isEmpty {
                Text("No matching tasks", bundle: .module)
            } else if allowsMutations {
                Text("Drag tasks here", bundle: .module)
            } else {
                Text("No tasks", bundle: .module)
            }
        }
        .font(VikuFont.footnote)
        .foregroundStyle(isTargeted ? highlightColor : palette.textTertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VikuSpacing.md)
        .padding(.vertical, VikuSpacing.xl)
        .background {
            RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
                .strokeBorder(
                    isTargeted ? highlightColor : palette.textTertiary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [VikuSpacing.xs, VikuSpacing.xs]),
                )
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(verbatim: bucket.title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            capacityBadge

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

    private var capacityBadge: some View {
        Group {
            if bucket.isFull {
                Text("\(bucket.tasks.count)/\(bucket.limit) Full", bundle: .module)
                    .bold()
            } else {
                Text(verbatim: bucket.limit > 0 ? "\(bucket.tasks.count)/\(bucket.limit)" : "\(bucket.tasks.count)")
            }
        }
        .font(VikuFont.caption)
        .foregroundStyle(bucket.isFull ? palette.semanticDangerForeground : palette.textSecondary)
        .padding(.horizontal, VikuSpacing.xs + VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.xxs)
        .background(
            bucket.isFull ? palette.semanticDanger : palette.fieldBackground,
            in: Capsule(),
        )
        .accessibilityValue(Text(verbatim: bucket.limit > 0
                ? "\(bucket.tasks.count)/\(bucket.limit)" : "\(bucket.tasks.count)"))
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
