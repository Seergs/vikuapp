import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The "Home Screen" row's picker: choose "Today" (the default digest) or
/// pin a project/saved filter as the Home tab's content instead.
///
/// Not the shared `ProjectPickerSheet` itself (saved filters have no
/// hierarchy, and a leading "Today" row doesn't fit its "None" semantics),
/// but its "Projects" section reuses `ProjectPickerTree`'s collapsible
/// hierarchy — same disclosure-chevron behavior as every other project
/// picker in the app — rather than a flat, unexpandable list.
struct HomeSelectionPickerSheet: View {
    let projects: [Project]
    let selectedID: Int?
    let onSelect: (Project?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expandedIDs: Set<EntityID> = []
    @State private var didSeedExpansion = false

    private var realProjects: [Project] {
        projects.filter { $0.kind == .project }
    }

    private var savedFilters: [Project] {
        projects.filter { $0.kind == .savedFilter }.sorted { $0.title < $1.title }
    }

    /// The project tree flattened to the rows currently visible, honoring
    /// `expandedIDs`. A collapsed node contributes only itself. Mirrors
    /// `ProjectPickerSheet.visibleRows`.
    private var visibleProjectRows: [ProjectRow] {
        func flatten(_ nodes: [ProjectPickerNode], depth: Int) -> [ProjectRow] {
            nodes.flatMap { node -> [ProjectRow] in
                let row = ProjectRow(node: node, depth: depth)
                guard !node.children.isEmpty, expandedIDs.contains(node.id) else { return [row] }
                return [row] + flatten(node.children, depth: depth + 1)
            }
        }
        return flatten(ProjectPickerTree.tree(from: realProjects), depth: 0)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Row(
                        icon: "calendar.badge.checkmark",
                        hexColor: "",
                        title: String(localized: "Today", bundle: .module),
                        isSelected: selectedID == nil,
                        onSelect: { select(nil) },
                    )
                }

                if !realProjects.isEmpty {
                    Section(String(localized: "Projects", bundle: .module)) {
                        ForEach(visibleProjectRows) { row in
                            ProjectTreeRow(
                                project: row.node.project,
                                hasChildren: !row.node.children.isEmpty,
                                depth: row.depth,
                                isExpanded: expandedIDs.contains(row.node.id),
                                isSelected: row.node.project.id.remoteValue == selectedID,
                                onToggleExpand: { toggleExpansion(row.node.id) },
                                onSelect: { select(row.node.project) },
                            )
                        }
                    }
                }

                if !savedFilters.isEmpty {
                    Section(String(localized: "Saved Filters", bundle: .module)) {
                        ForEach(savedFilters) { filter in
                            Row(
                                icon: "line.3.horizontal.decrease.circle.fill",
                                hexColor: "",
                                title: filter.title,
                                isSelected: filter.id.remoteValue == selectedID,
                                onSelect: { select(filter) },
                            )
                        }
                    }
                }
            }
            .navigationTitle(Text("Home Screen", bundle: .module))
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancel", bundle: .module))
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !didSeedExpansion else { return }
            didSeedExpansion = true
            expandedIDs = ProjectPickerTree.ancestorIDs(of: selectedID.map(EntityID.remote), in: realProjects)
        }
    }

    private func toggleExpansion(_ id: EntityID) {
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

    private struct ProjectRow: Identifiable {
        let node: ProjectPickerNode
        let depth: Int
        var id: EntityID {
            node.id
        }
    }

    /// "Today" and saved-filter rows: no indentation or disclosure chevron,
    /// neither has a hierarchy.
    private struct Row: View {
        let icon: String
        let hexColor: String
        let title: String
        let isSelected: Bool
        let onSelect: () -> Void

        @Environment(\.vikuPalette) private var palette

        var body: some View {
            HStack(spacing: VikuSpacing.sm) {
                Color.clear.frame(width: 20, height: 28)

                Button(action: onSelect) {
                    HStack(spacing: VikuSpacing.sm) {
                        Image(systemName: icon)
                            .font(VikuFont.body)
                            .foregroundStyle(Color(vikuHex: hexColor) ?? palette.brand)
                            .frame(width: 24, alignment: .center)

                        Text(verbatim: title)
                            .font(VikuFont.body)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Spacer(minLength: VikuSpacing.sm)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(VikuFont.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(palette.brand)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A real project's row: disclosure chevron when it has subprojects,
    /// indented by `depth`, and `ProjectPickerIcon` so a parent/leaf project
    /// reads the same way as every other project picker. Mirrors
    /// `ProjectPickerSheet`'s own (file-private) row.
    private struct ProjectTreeRow: View {
        let project: Project
        let hasChildren: Bool
        let depth: Int
        let isExpanded: Bool
        let isSelected: Bool
        let onToggleExpand: () -> Void
        let onSelect: () -> Void

        @Environment(\.vikuPalette) private var palette

        var body: some View {
            HStack(spacing: VikuSpacing.sm) {
                if hasChildren {
                    Button(action: onToggleExpand) {
                        Image(systemName: "chevron.right")
                            .font(VikuFont.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.textTertiary)
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
                                .foregroundStyle(palette.brand)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * VikuSpacing.md)
        }
    }
}
