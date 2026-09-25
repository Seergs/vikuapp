import SwiftUI
import VikunjaCore

/// The shared "pick a project" sheet, in the style of Apple Notes' "Move to
/// Folder": a native inset-grouped list (rows on a card surface distinctly
/// above the sheet's own background, native separators and press feedback)
/// where any project with subprojects expands and collapses behind a
/// disclosure chevron, to arbitrary depth. Replaces the hand-rolled
/// `ScrollView`-of-`Button`s picker that used to be copy-pasted across the
/// quick-add, create/edit-project, and "move task" screens, each backed by
/// its own two-level `ProjectGroup` grouping.
///
/// Presented as a `.sheet` by the caller. Selection is committed by tapping a
/// row (which dismisses); the "Cancel" toolbar button closes without
/// changing anything.
public struct ProjectPickerSheet: View {
    /// Caller-supplied, opaque display text (see `FieldLabel`'s doc comment
    /// on `TaskFormControls.swift`): each caller's feature owns and
    /// localizes its own title, this sheet just renders it verbatim.
    private let title: String
    private let projects: [Project]
    private let selectedProjectID: Int?
    private let showsNoneOption: Bool
    private let excludedID: Int?
    private let onSelect: (Project?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expandedIDs: Set<Int> = []
    @State private var didSeedExpansion = false

    /// - Parameters:
    ///   - title: the navigation-bar title, e.g. `"Choose Project"`.
    ///   - projects: the flat project list to offer (the caller filters out
    ///     archived projects; the tree is built here).
    ///   - selectedProjectID: the currently-chosen project, for the checkmark
    ///     and to pre-expand its branch.
    ///   - showsNoneOption: when `true`, a leading "None" row that selects
    ///     `nil` (a root-level project / no parent).
    ///   - excludingSubtreeOf: a project id whose whole subtree is hidden —
    ///     the parent-project pickers pass the project being edited; the
    ///     "move task" pickers pass the task's current project.
    ///   - onSelect: the picked project, or `nil` for the "None" row. Called
    ///     after the sheet dismisses.
    public init(
        title: String,
        projects: [Project],
        selectedProjectID: Int?,
        showsNoneOption: Bool = false,
        excludingSubtreeOf: Int? = nil,
        onSelect: @escaping (Project?) -> Void,
    ) {
        self.title = title
        self.projects = projects
        self.selectedProjectID = selectedProjectID
        self.showsNoneOption = showsNoneOption
        self.excludedID = excludingSubtreeOf
        self.onSelect = onSelect
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The tree flattened to the rows currently visible, honoring
    /// `expandedIDs`. A collapsed node contributes only itself.
    private var visibleRows: [Row] {
        func flatten(_ nodes: [ProjectPickerNode], depth: Int) -> [Row] {
            nodes.flatMap { node -> [Row] in
                let row = Row(node: node, depth: depth)
                guard !node.children.isEmpty, expandedIDs.contains(node.id) else { return [row] }
                return [row] + flatten(node.children, depth: depth + 1)
            }
        }
        return flatten(ProjectPickerTree.tree(from: projects, excludingSubtreeOf: excludedID), depth: 0)
    }

    private var searchResults: [Project] {
        ProjectPickerTree.flatMatches(projects, query: query, excludingSubtreeOf: excludedID)
    }

    public var body: some View {
        NavigationStack {
            List {
                if showsNoneOption, !isSearching {
                    NoneRow(isSelected: selectedProjectID == nil) { select(nil) }
                }

                if isSearching {
                    ForEach(searchResults) { project in
                        ProjectRow(
                            project: project,
                            hasChildren: false,
                            depth: 0,
                            isExpanded: false,
                            isSelected: project.id == selectedProjectID,
                            onToggleExpand: {},
                            onSelect: { select(project) },
                        )
                    }
                } else {
                    ForEach(visibleRows) { row in
                        ProjectRow(
                            project: row.node.project,
                            hasChildren: !row.node.children.isEmpty,
                            depth: row.depth,
                            isExpanded: expandedIDs.contains(row.node.id),
                            isSelected: row.node.project.id == selectedProjectID,
                            onToggleExpand: { toggleExpansion(row.node.id) },
                            onSelect: { select(row.node.project) },
                        )
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Search projects...", bundle: .module))
            .navigationTitle(title)
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !didSeedExpansion else { return }
            didSeedExpansion = true
            expandedIDs = ProjectPickerTree.ancestorIDs(of: selectedProjectID, in: projects)
        }
    }

    private func toggleExpansion(_ id: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            if !expandedIDs.insert(id).inserted {
                expandedIDs.remove(id)
            }
        }
    }

    private func select(_ project: Project?) {
        dismiss()
        onSelect(project)
    }

    private struct Row: Identifiable {
        let node: ProjectPickerNode
        let depth: Int
        var id: Int {
            node.id
        }
    }
}

/// The tinted project glyph shared by the picker rows and the collapsed
/// "Project" / "Parent Project" fields that open the picker. `folder.fill`
/// signals "has subprojects" (Finder/Notes convention); a leaf project — a
/// plain task list — gets `list.bullet.rectangle.fill`. Tinted with the
/// project's own color, falling back to the brand color when unset.
public struct ProjectPickerIcon: View {
    private let hexColor: String
    private let hasChildren: Bool

    public init(hexColor: String, hasChildren: Bool = false) {
        self.hexColor = hexColor
        self.hasChildren = hasChildren
    }

    public var body: some View {
        Image(systemName: hasChildren ? "folder.fill" : "list.bullet.rectangle.fill")
            .font(VikuFont.body)
            .foregroundStyle(Color(vikuHex: hexColor) ?? VikuColor.brandPrimary)
            .frame(width: 24, alignment: .center)
    }
}

private struct ProjectRow: View {
    let project: Project
    let hasChildren: Bool
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpand: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            if hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(VikuFont.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(VikuColor.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 20, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 20, height: 28)
            }

            Button(action: onSelect) {
                HStack(spacing: VikuSpacing.sm) {
                    ProjectPickerIcon(hexColor: project.hexColor, hasChildren: hasChildren)

                    Text(project.title)
                        .font(VikuFont.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: VikuSpacing.sm)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(VikuFont.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(VikuColor.brandPrimary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * VikuSpacing.md)
    }
}

private struct NoneRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            Color.clear.frame(width: 20, height: 28)

            Button(action: onSelect) {
                HStack(spacing: VikuSpacing.sm) {
                    Image(systemName: "folder")
                        .font(VikuFont.body)
                        .foregroundStyle(VikuColor.textTertiary)
                        .frame(width: 24, alignment: .center)

                    Text("None", bundle: .module)
                        .font(VikuFont.body)
                        .foregroundStyle(Color.primary)

                    Spacer(minLength: VikuSpacing.sm)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(VikuFont.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(VikuColor.brandPrimary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
