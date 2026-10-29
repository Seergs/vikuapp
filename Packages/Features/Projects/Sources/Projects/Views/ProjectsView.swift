import Foundation
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

/// The Projects tab's list screen: a flattened, indented rendering of
/// `ProjectsListViewModel.rootNodes` (a parent/child tree keyed by
/// `parentProjectID`), with per-project expand/collapse.
struct ProjectsView: View {
    @Bindable var viewModel: ProjectsListViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.vikuPalette) private var palette
    let makeCreateProjectViewModel: (EntityID?) -> CreateProjectViewModel
    let makeEditProjectViewModel: (Project) -> EditProjectViewModel
    let makeRenameFilterViewModel: (Project) -> RenameFilterViewModel
    @State private var expandedProjectIDs: Set<EntityID> = []
    @State private var isShowingCreateProject = false
    @State private var projectPendingDelete: ProjectNode?
    @State private var editingProject: Project?
    @State private var renamingFilterProject: Project?
    @State private var subprojectParentProject: Project?

    var body: some View {
        // `List` stays the root container across every load state — not just
        // `.loaded` — so the container backing the large title never swaps
        // out for a plain centered `VStack` mid-transition (which used to
        // drop the "Projects" title down the screen) and so the
        // `.refreshable` task, owned by this `List`, never gets torn down
        // and cancelled by a state change mid-refresh.
        content
            .projectsListStyle()
            .scrollContentBackground(.hidden)
            .background(palette.pageBackground)
            .refreshable { await viewModel.load() }
            .navigationTitle(Text("Projects", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingCreateProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("New Project", bundle: .module))
                }
            }
            .sheet(isPresented: $isShowingCreateProject, onDismiss: {
                Task { await viewModel.load() }
            }, content: {
                CreateProjectSheetView(makeViewModel: { makeCreateProjectViewModel(nil) })
            })
            .sheet(item: $editingProject, onDismiss: {
                Task { await viewModel.load() }
            }, content: { project in
                EditProjectSheetView(makeViewModel: { makeEditProjectViewModel(project) })
            })
            .sheet(item: $renamingFilterProject, onDismiss: {
                Task { await viewModel.load() }
            }, content: { project in
                RenameFilterSheetView(makeViewModel: { makeRenameFilterViewModel(project) })
            })
            .sheet(item: $subprojectParentProject, onDismiss: {
                Task { await viewModel.load() }
            }, content: { parentProject in
                CreateProjectSheetView(makeViewModel: { makeCreateProjectViewModel(parentProject.id) })
            })
            .confirmationDialog(
                Text(verbatim: deleteConfirmationMessage),
                isPresented: Binding(
                    get: { projectPendingDelete != nil },
                    set: { isPresented in
                        if !isPresented {
                            projectPendingDelete = nil
                        }
                    },
                ),
                titleVisibility: .visible,
            ) {
                if let projectPendingDelete {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteProject(projectPendingDelete) }
                    } label: {
                        if projectPendingDelete.project.kind == .savedFilter {
                            Text("Delete Filter", bundle: .module)
                        } else {
                            Text("Delete Project", bundle: .module)
                        }
                    }
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            }
            .task {
                await viewModel.load()
            }
    }

    private var content: some View {
        List {
            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, VikuSpacing.xxl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            case let .failure(message):
                VikuStatusView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: String(localized: "Couldn't load projects", bundle: .module),
                    message: message,
                ) {
                    Task { await viewModel.load() }
                }
                .padding(.top, VikuSpacing.xxl)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            case .loaded where viewModel.rootNodes.isEmpty && viewModel.pseudoNodes.isEmpty:
                VikuStatusView(
                    systemImage: "folder.badge.plus",
                    title: String(localized: "No projects yet", bundle: .module),
                    message: String(
                        localized: "Projects you create on your Vikunja instance will show up here.",
                        bundle: .module,
                    ),
                )
                .padding(.top, VikuSpacing.xxl)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            case .loaded:
                if !viewModel.pseudoNodes.isEmpty {
                    Section {
                        ForEach(viewModel.pseudoNodes) { node in
                            PseudoProjectRow(
                                project: node.project,
                                taskSummary: node.id.remoteValue.flatMap { viewModel.taskSummaries[$0] },
                                onSelect: { router.push(ProjectsRoute.projectOverview(node)) },
                                onRename: { renamingFilterProject = $0 },
                                onDelete: { projectPendingDelete = node },
                            )
                        }
                    } header: {
                        Text("Favorites & Filters", bundle: .module)
                            .vikuSectionHeader()
                    }
                    .listRowBackground(palette.cardBackground)
                }

                if !viewModel.rootNodes.isEmpty {
                    Section {
                        ForEach(Self.flatten(viewModel.rootNodes, expandedProjectIDs: expandedProjectIDs)) { row in
                            ProjectRow(
                                project: row.node.project,
                                taskSummary: row.node.id.remoteValue.flatMap { viewModel.taskSummaries[$0] },
                                level: row.level,
                                hasChildren: !row.node.children.isEmpty,
                                isExpanded: expandedProjectIDs.contains(row.node.id),
                                onSelect: { router.push(ProjectsRoute.projectOverview(row.node)) },
                                onToggleExpand: { toggleExpanded(row.node.id) },
                                onEdit: { editingProject = $0 },
                                onDelete: { projectPendingDelete = row.node },
                                onAddSubproject: { subprojectParentProject = row.node.project },
                            )
                        }
                    } header: {
                        Text("My Projects", bundle: .module)
                            .vikuSectionHeader()
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
        }
    }

    private var deleteConfirmationMessage: String {
        if projectPendingDelete?.project.kind == .savedFilter {
            return String(localized: "This permanently deletes the saved filter.", bundle: .module)
        }
        let hasChildren = projectPendingDelete?.children.isEmpty == false
        return hasChildren
            ? String(
                localized: "This permanently deletes the project, its subprojects, and all their tasks.",
                bundle: .module,
            )
            : String(localized: "This permanently deletes the project and all its tasks.", bundle: .module)
    }

    private func toggleExpanded(_ id: EntityID) {
        withAnimation(.snappy) {
            if expandedProjectIDs.contains(id) {
                expandedProjectIDs.remove(id)
            } else {
                expandedProjectIDs.insert(id)
            }
        }
    }

    private static func flatten(
        _ nodes: [ProjectNode],
        level: Int = 0,
        expandedProjectIDs: Set<EntityID>,
    ) -> [ProjectDisplayRow] {
        nodes.flatMap { node -> [ProjectDisplayRow] in
            var rows = [ProjectDisplayRow(node: node, level: level)]
            if expandedProjectIDs.contains(node.id) {
                rows += flatten(node.children, level: level + 1, expandedProjectIDs: expandedProjectIDs)
            }
            return rows
        }
    }
}

private struct ProjectDisplayRow: Identifiable {
    let node: ProjectNode
    let level: Int
    var id: EntityID {
        node.id
    }
}

/// A row for Favorites or a saved filter: `VikuProjectKindSwatch` in place of
/// a project's hex-color dot, no indentation, no expand chevron (neither
/// pseudo-project kind nests). Its context menu mirrors what
/// `ProjectOverviewView`'s own "..." menu offers that same project kind: a
/// saved filter can be renamed/deleted (never "Add Subproject" - it can't own
/// one), Favorites offers nothing (a fixed pseudo-list with no row of its own
/// on the server - see `FilterRepositoryProtocol`, `ProjectKind`). Below the
/// title: a kind badge ("Favorites"/"Saved Filter") and, once its task
/// summary has arrived, a "N pending" count next to it.
private struct PseudoProjectRow: View {
    let project: Project
    let taskSummary: ProjectTaskSummary?
    let onSelect: () -> Void
    let onRename: (Project) -> Void
    let onDelete: () -> Void

    @Environment(\.vikuPalette) private var palette
    @Environment(\.pendingSyncStatuses) private var pendingSyncStatuses

    private var syncStatus: SyncItemStatus? {
        guard project.kind == .savedFilter else { return nil }
        return pendingSyncStatuses[SyncItemKey(kind: .project, id: project.id)]
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            VikuProjectKindSwatch(kind: project.kind)

            VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                HStack(spacing: VikuSpacing.xs) {
                    Text(project.title)
                        .font(VikuFont.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if let syncStatus {
                        VikuPendingSyncIndicator(status: syncStatus)
                    }
                }

                HStack(spacing: VikuSpacing.sm) {
                    PseudoProjectKindBadge(kind: project.kind)

                    if let taskSummary {
                        Text(Self.pendingText(for: taskSummary))
                            .font(VikuFont.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }

            Spacer(minLength: VikuSpacing.sm)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if project.kind == .savedFilter {
                Button(
                    String(localized: "Rename Filter", bundle: .module),
                    systemImage: "pencil",
                    action: { onRename(project) },
                )
                // `role: .destructive` alone renders blue here, not red: the
                // tab bar's brand tint leaks into the context menu and
                // overrides the role's tint. Pin it back to danger.
                Button(
                    String(localized: "Delete Filter", bundle: .module),
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete,
                )
                .tint(palette.semanticDanger)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(project.title)
    }

    private static func pendingText(for summary: ProjectTaskSummary) -> String {
        String(localized: "\(summary.total - summary.done) pending", bundle: .module)
    }
}

/// The "Favorites"/"Saved Filter" label under a pseudo-project's title —
/// same filled-capsule shape as `VikuLabelChip`, tinted via
/// `VikuColor.ProjectBadge` so it matches `VikuProjectKindSwatch`'s border.
private struct PseudoProjectKindBadge: View {
    let kind: ProjectKind

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        Group {
            switch kind {
            case .favorites: Text("Favorites", bundle: .module)
            case .savedFilter: Text("Saved Filter", bundle: .module)
            case .project: Text(verbatim: "")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        // Plain neutral gray, text included — the favorite/filter tint
        // already lives on the swatch (border + icon); the badge is just a
        // kind label, not a second place to repeat that color.
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.vertical, VikuSpacing.xxs)
        .background(Capsule().fill(palette.textTertiary.opacity(0.18)))
    }
}

/// A single row: a color swatch (from the project's `hexColor`, falling back
/// to the brand color when unset), title, a task-completion progress bar +
/// `done/total` count when the project has tasks, and — only when the project
/// has children — a disclosure chevron. Tapping the row itself opens that
/// project's overview; the chevron is its own tap target that only
/// expands/collapses the children, so opening a parent project doesn't
/// require first collapsing it.
private struct ProjectRow: View {
    let project: Project
    let taskSummary: ProjectTaskSummary?
    let level: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggleExpand: () -> Void
    let onEdit: (Project) -> Void
    let onDelete: () -> Void
    let onAddSubproject: () -> Void

    @Environment(\.vikuPalette) private var palette
    @Environment(\.pendingSyncStatuses) private var pendingSyncStatuses

    private var swatchColor: Color {
        Color(vikuHex: project.hexColor) ?? palette.brand
    }

    private var syncStatus: SyncItemStatus? {
        pendingSyncStatuses[SyncItemKey(kind: .project, id: project.id)]
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous)
                .fill(swatchColor.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(swatchColor)
                        .frame(width: 12, height: 12)
                }

            VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                HStack(spacing: VikuSpacing.xs) {
                    Text(project.title)
                        .font(VikuFont.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if let syncStatus {
                        VikuPendingSyncIndicator(status: syncStatus)
                    }
                }

                // The second line always occupies the same height, whether or
                // not this project's task summary has arrived yet — its own
                // request lands after the tree renders, and letting the row
                // grow when it does shifts every row below it. Until then a
                // redacted skeleton holds the space; a project that turns out
                // to have no tasks keeps the line as "No tasks" rather than
                // collapsing it (which would shift the row a second time).
                Group {
                    if let taskSummary {
                        if taskSummary.total > 0 {
                            ProjectProgressCount(summary: taskSummary, color: swatchColor)
                        } else {
                            Text("No tasks", bundle: .module)
                                .font(VikuFont.caption)
                                .foregroundStyle(palette.textTertiary)
                        }
                    } else {
                        ProjectProgressCount(
                            summary: ProjectTaskSummary(done: 0, total: 1),
                            color: swatchColor,
                        )
                        .redacted(reason: .placeholder)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: taskSummary)
            }

            Spacer(minLength: VikuSpacing.sm)

            if hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isExpanded
                        ? Text("Collapse", bundle: .module)
                        : Text("Expand", bundle: .module),
                )
            }
        }
        .padding(.leading, CGFloat(level) * VikuSpacing.lg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(
                String(localized: "Edit Project", bundle: .module),
                systemImage: "pencil",
                action: { onEdit(project) },
            )
            Button(
                String(localized: "Add Subproject", bundle: .module),
                systemImage: "folder.badge.plus",
                action: onAddSubproject,
            )
            // `role: .destructive` alone renders blue here, not red: the tab
            // bar's brand tint leaks into the context menu and overrides the
            // role's tint. Pin it back to danger.
            Button(
                String(localized: "Delete Project", bundle: .module),
                systemImage: "trash",
                role: .destructive,
                action: onDelete,
            )
            .tint(palette.semanticDanger)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(project.title)
    }
}

/// The design's per-project progress affordance: a slim completion bar
/// capped at 120pt wide, followed by a `done/total` count.
private struct ProjectProgressCount: View {
    let summary: ProjectTaskSummary
    let color: Color

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.fieldBackground)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * summary.fraction)
                }
            }
            .frame(width: 120, height: 4)

            Text(verbatim: "\(summary.done)/\(summary.total)")
                .font(VikuFont.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(summary.done) of \(summary.total) tasks completed", bundle: .module),
        )
    }
}

/// `.insetGrouped` is iOS/watchOS-only, but this package also builds for
/// macOS to run its tests — falls back to the default style there.
private extension View {
    @ViewBuilder
    func projectsListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        self
        #endif
    }
}
