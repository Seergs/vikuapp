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
    /// Fired with the trimmed search text when the user taps the "Create as
    /// new task" row. `nil` hides that row entirely, so callers that don't
    /// support inline creation yet see no change.
    let onCreateNew: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vikuPalette) private var palette
    @State private var query = ""

    public init(
        kind: RelationKind,
        results: [VikunjaTask],
        projectTitle: @escaping (VikunjaTask) -> String?,
        onAppear: @escaping () async -> Void,
        onSearch: @escaping (String) async -> Void,
        onSelect: @escaping (VikunjaTask) -> Void,
        onCreateNew: ((String) -> Void)? = nil,
    ) {
        self.kind = kind
        self.results = results
        self.projectTitle = projectTitle
        self.onAppear = onAppear
        self.onSearch = onSearch
        self.onSelect = onSelect
        self.onCreateNew = onCreateNew
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// Shown once the user has typed something to create — there's nothing
    /// to prefill a new task's title with otherwise, so the empty-query
    /// suggestions list behaves exactly as it did before this row existed.
    private var showsCreateRow: Bool {
        onCreateNew != nil && isSearching
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if results.isEmpty {
                        VStack {
                            Spacer()
                            Text(
                                isSearching
                                    ? String(localized: "No results", bundle: .module)
                                    : String(localized: "No other tasks in this project", bundle: .module),
                            )
                            .font(VikuFont.subheadline)
                            .foregroundStyle(palette.textTertiary)
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
                if showsCreateRow {
                    Divider()
                    createNewRow
                }
            }
            .searchable(text: $query, prompt: Text("Search tasks...", bundle: .module))
            .onChange(of: query) { _, newValue in
                Task { await onSearch(newValue) }
            }
            .navigationTitle(kind.localizedDisplayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .task { await onAppear() }
    }

    private var createNewRow: some View {
        Button {
            onCreateNew?(trimmedQuery)
        } label: {
            HStack(spacing: VikuSpacing.sm) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.brand)
                Text(String(localized: "Create \"\(trimmedQuery)\" as new task", bundle: .module))
                    .font(VikuFont.subheadline)
                    .foregroundStyle(palette.brand)
                Spacer()
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RelationCandidateRow: View {
    let task: VikunjaTask
    let projectTitle: String?

    @Environment(\.vikuPalette) private var palette

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
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.brand)
        }
    }
}
