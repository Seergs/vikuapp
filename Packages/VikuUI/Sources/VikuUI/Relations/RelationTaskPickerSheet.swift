import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Searches for the other side of a new relation of the given `kind`.
/// Driven entirely by closures/values rather than a concrete view model —
/// `results` is whatever the caller's most recent search/suggestions call
/// produced, `onAppear` primes it (suggestions + project names) and
/// `onSearch` reruns it as the query changes — so it lives in `VikuUI`
/// rather than `Features/Tasks`, mirroring `LabelPickerSheet`: every screen
/// that lists tasks (Today, a project's task list, the task detail overflow
/// menu) can offer "add relation" without importing another feature.
public struct RelationTaskPickerSheet: View {
    let kind: RelationKind
    let results: [VikunjaTask]
    let projectTitle: (VikunjaTask) -> String?
    let onAppear: () async -> Void
    let onSearch: (String) async -> Void
    let onSelect: (VikunjaTask) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    public init(
        kind: RelationKind,
        results: [VikunjaTask],
        projectTitle: @escaping (VikunjaTask) -> String?,
        onAppear: @escaping () async -> Void,
        onSearch: @escaping (String) async -> Void,
        onSelect: @escaping (VikunjaTask) -> Void,
    ) {
        self.kind = kind
        self.results = results
        self.projectTitle = projectTitle
        self.onAppear = onAppear
        self.onSearch = onSearch
        self.onSelect = onSelect
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    VStack {
                        Spacer()
                        Text(isSearching ? "No results" : "No other tasks in this project")
                            .font(VikuFont.subheadline)
                            .foregroundStyle(VikuColor.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { candidate in
                        Button {
                            onSelect(candidate)
                        } label: {
                            RelationCandidateRow(
                                task: candidate,
                                projectTitle: projectTitle(candidate),
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search tasks...")
            .onChange(of: query) { _, newValue in
                Task { await onSearch(newValue) }
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
        .task { await onAppear() }
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
