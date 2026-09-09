import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The two steps of adding a relation, matching the design mockup: first
/// pick a relation kind, then pick the other task. Modeled as one
/// `Identifiable` enum (rather than two independent `Bool`s) so exactly one
/// sheet is ever presented at a time and picking a kind can hand off
/// straight into the task picker.
enum RelationSheetStep: Identifiable {
    case pickKind
    case pickTask(RelationKind)

    var id: String {
        switch self {
        case .pickKind: "pickKind"
        case let .pickTask(kind): "pickTask-\(kind.rawValue)"
        }
    }
}

/// Lets the user choose which kind of relation to add — every `RelationKind`
/// except `subtask`/`parenttask`, which are represented on this screen
/// through the (read-only, for now) Subtasks checklist instead.
struct RelationKindPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (RelationKind) -> Void

    private var kinds: [RelationKind] {
        RelationKind.allCases.filter { $0 != .subtask && $0 != .parenttask }
    }

    var body: some View {
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

/// Searches every task on the instance (via
/// `TaskDetailViewModel.searchTasksForRelation(query:)`) to pick the other
/// side of a new relation of the given `kind`.
struct RelationTaskPickerSheet: View {
    @Bindable var viewModel: TaskDetailViewModel
    let kind: RelationKind
    let onSelect: (VikunjaTask) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.relationSearchResults.isEmpty {
                    VStack {
                        Spacer()
                        Text(isSearching ? "No results" : "No other tasks in this project")
                            .font(VikuFont.subheadline)
                            .foregroundStyle(VikuColor.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.relationSearchResults) { candidate in
                        Button {
                            onSelect(candidate)
                        } label: {
                            RelationCandidateRow(
                                task: candidate,
                                projectTitle: viewModel.projectTitle(forProjectID: candidate.projectID),
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search tasks...")
            .onChange(of: query) { _, newValue in
                Task { await viewModel.searchTasksForRelation(query: newValue) }
            }
            .navigationTitle(kind.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.loadAllProjects()
            await viewModel.loadRelationSuggestions()
        }
    }
}

private struct RelationCandidateRow: View {
    let task: VikunjaTask
    let projectTitle: String?

    private var priorityColor: Color? {
        switch task.priority {
        case .unset: nil
        case .low: VikuColor.Priority.low
        case .medium: VikuColor.Priority.medium
        case .high: VikuColor.Priority.high
        case .urgent, .doNow: VikuColor.Priority.urgent
        }
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            if let priorityColor {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                if let projectTitle {
                    Text(projectTitle)
                        .font(VikuFont.caption)
                        .foregroundStyle(VikuColor.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VikuColor.brandPrimary)
        }
    }
}
