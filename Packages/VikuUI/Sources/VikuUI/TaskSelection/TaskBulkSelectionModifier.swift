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
    @State private var isConfirming = false
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .disabled(selection.isDeleting)
            .preference(key: TaskBulkSelectionActiveKey.self, value: selection.isSelecting)
            .toolbar {
                if selection.isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: selection.reset) {
                            Text("Cancel", bundle: .module)
                        }
                        .disabled(selection.isDeleting)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            selection.selectAll(visibleTasks)
                        } label: {
                            Text("Select All", bundle: .module)
                        }
                        .disabled(selection.isDeleting || visibleTasks.isEmpty)
                    }
                }
            }
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
            .onDisappear {
                isConfirming = false
                selection.reset()
            }
    }

    private var selectionBar: some View {
        HStack(spacing: VikuSpacing.md) {
            Text("\(selection.selectedIDs.count) selected", bundle: .module)
                .font(VikuFont.subheadline)
                .foregroundStyle(palette.textSecondary)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: VikuSpacing.sm)
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                VStack(spacing: VikuSpacing.xxs) {
                    Image(systemName: "trash")
                        .font(VikuFont.title3)
                    Group {
                        if selection.isDeleting {
                            Text("Deleting…", bundle: .module)
                        } else {
                            Text("Delete", bundle: .module)
                        }
                    }
                    .font(VikuFont.caption2)
                    .fontWeight(.bold)
                }
                .padding(.horizontal, VikuSpacing.sm)
                .padding(.vertical, VikuSpacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                selection.selectedIDs.isEmpty || selection.isDeleting ? palette.textTertiary : palette.semanticDanger,
            )
            .disabled(selection.selectedIDs.isEmpty || selection.isDeleting)
        }
        .padding(VikuSpacing.md)
        .background {
            Rectangle()
                .fill(.bar)
                .shadow(color: VikuColor.barShadow, radius: VikuSpacing.sm, x: 0, y: -VikuSpacing.xs)
        }
    }
}

public extension View {
    func taskBulkSelection(
        _ selection: TaskBulkSelection,
        visibleTasks: [VikunjaTask],
        onDelete: @escaping () async -> Void,
    ) -> some View {
        modifier(TaskBulkSelectionModifier(selection: selection, visibleTasks: visibleTasks, onDelete: onDelete))
    }
}
