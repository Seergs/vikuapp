import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Lets the app shell suppress its floating creation button during selection.
public struct TaskBulkSelectionActiveKey: PreferenceKey {
    public static var defaultValue: Bool {
        false
    }

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue() || value
    }
}

/// Shared menu entry keeps selection vocabulary in the owning module's catalog.
public struct TaskBulkSelectionAction: View {
    let selection: TaskBulkSelection

    public init(selection: TaskBulkSelection) {
        self.selection = selection
    }

    public var body: some View {
        Button(action: selection.begin) {
            Label { Text("Select Tasks", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
        }
    }
}

private struct TaskBulkSelectionModifier: ViewModifier {
    let selection: TaskBulkSelection
    let visibleTasks: [VikunjaTask]
    let onDelete: () async -> Void
    let onSetCompletion: (Bool) async -> Void
    @State private var isConfirming = false
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .disabled(selection.isPerformingAction)
            .preference(key: TaskBulkSelectionActiveKey.self, value: selection.isSelecting)
            .toolbar { selectionToolbar }
            .safeAreaInset(edge: .bottom) {
                if selection.isSelecting {
                    selectionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selection.isSelecting)
            .confirmationDialog(
                Text("Delete \(selection.selectedIDs.count) tasks?", bundle: .module),
                isPresented: $isConfirming,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) {
                    Task { await onDelete() }
                } label: {
                    Text("Delete \(selection.selectedIDs.count) tasks", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text("This action cannot be undone.", bundle: .module)
            }
            .onChange(of: visibleTasks.map(\.id)) { _, _ in
                selection.reconcile(with: visibleTasks)
                if selection.selectedIDs.isEmpty {
                    isConfirming = false
                }
            }
            .onChange(of: selection.isSelecting) { _, isSelecting in
                if !isSelecting {
                    isConfirming = false
                }
            }
            .onChange(of: selection.isPerformingAction) { _, isPerforming in
                if !isPerforming {
                    selection.reconcile(with: visibleTasks)
                }
            }
            .onDisappear {
                isConfirming = false
                selection.reset()
            }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if selection.isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: selection.reset) {
                    Text("Cancel", bundle: .module)
                }
                .disabled(selection.isPerformingAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection.selectAll(visibleTasks)
                } label: {
                    Text("Select All", bundle: .module)
                }
                .disabled(selection.isPerformingAction || visibleTasks.isEmpty)
            }
        }
    }

    private var selectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VikuSpacing.md) {
                selectionCount
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: VikuSpacing.sm)
                selectionActions
            }
            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                selectionCount
                HStack(spacing: VikuSpacing.md) {
                    Spacer(minLength: VikuSpacing.sm)
                    selectionActions
                }
            }
        }
        .padding(VikuSpacing.md)
        .background {
            Rectangle()
                .fill(.bar)
                .shadow(color: VikuColor.barShadow, radius: VikuSpacing.sm, x: 0, y: -VikuSpacing.xs)
        }
    }

    private var selectionCount: some View {
        Text("\(selection.selectedIDs.count) selected", bundle: .module)
            .font(VikuFont.subheadline)
            .foregroundStyle(palette.textSecondary)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var selectionActions: some View {
        Group {
            completionAction
                .foregroundStyle(actionsDisabled ? palette.textTertiary : palette.brand)
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                TaskSelectionActionLabel(
                    title: selection.isDeleting
                        ? String(localized: "Deleting…", bundle: .module)
                        : String(localized: "Delete", bundle: .module),
                    symbolName: "trash",
                )
            }
            .foregroundStyle(actionsDisabled ? palette.textTertiary : palette.semanticDanger)
        }
        .buttonStyle(.plain)
        .disabled(actionsDisabled)
    }

    private var actionsDisabled: Bool {
        selection.selectedIDs.isEmpty || selection.isPerformingAction
    }

    @ViewBuilder
    private var completionAction: some View {
        let target = selection.completionTarget(visibleTasks: visibleTasks)
        if let target {
            Button {
                Task { await onSetCompletion(target) }
            } label: {
                completionLabel(target: target)
            }
            .accessibilityLabel(target
                ? Text("Mark as Completed", bundle: .module)
                : Text("Mark as Pending", bundle: .module))
        } else {
            Menu {
                Button {
                    Task { await onSetCompletion(true) }
                } label: {
                    Text("Mark as Completed", bundle: .module)
                }
                Button {
                    Task { await onSetCompletion(false) }
                } label: {
                    Text("Mark as Pending", bundle: .module)
                }
            } label: {
                completionLabel(target: nil)
            }
        }
    }

    private func completionLabel(target: Bool?) -> some View {
        let title = if selection.isUpdatingCompletion {
            String(localized: "Updating…", bundle: .module)
        } else if let target {
            if target {
                String(localized: "Complete", bundle: .module)
            } else {
                String(localized: "Reopen", bundle: .module)
            }
        } else {
            String(localized: "Status", bundle: .module)
        }
        return TaskSelectionActionLabel(
            title: title, symbolName: target == false ? "arrow.uturn.backward.circle" : "checkmark",
        )
    }
}

public extension View {
    func taskBulkSelection(
        _ selection: TaskBulkSelection,
        visibleTasks: [VikunjaTask],
        onDelete: @escaping () async -> Void,
        onSetCompletion: @escaping (Bool) async -> Void,
    ) -> some View {
        modifier(TaskBulkSelectionModifier(
            selection: selection, visibleTasks: visibleTasks, onDelete: onDelete, onSetCompletion: onSetCompletion,
        ))
    }
}

private struct TaskSelectionActionLabel: View {
    let title: String
    let symbolName: String

    var body: some View {
        VStack(spacing: VikuSpacing.xxs) {
            Image(systemName: symbolName)
                .font(VikuFont.title3)
            Text(verbatim: title)
                .font(VikuFont.caption2)
                .fontWeight(.bold)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.vertical, VikuSpacing.xs)
        .contentShape(Rectangle())
    }
}
