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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.vikuIsOnline) private var isOnline
    @Environment(\.pendingSyncStatuses) private var pendingSyncStatuses
    let makeCreateProjectViewModel: (EntityID?) -> CreateProjectViewModel
    let makeEditProjectViewModel: (Project) -> EditProjectViewModel
    let makeRenameFilterViewModel: (Project) -> RenameFilterViewModel
    @State private var expandedProjectIDs: Set<EntityID> = []
    @State private var isShowingCreateProject = false
    @State private var projectPendingDelete: ProjectNode?
    @State private var editingProject: Project?
    @State private var renamingFilterProject: Project?
    @State private var subprojectParentProject: Project?
    @State private var createdProject: ProjectRevealRequest?
    @State private var projectToReveal: ProjectRevealRequest?
    @State private var projectToHighlight: EntityID?
    @State private var highlightedProjectID: EntityID?

    private static let revealScrollDuration: TimeInterval = 0.3

    var body: some View {
        projectList
            .projectsListStyle()
            // Let the last project's expand button scroll above the global quick-add overlay.
            .contentMargins(.bottom, VikuSpacing.xxl * 2, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(palette.pageBackground)
            .refreshable { await viewModel.refresh() }
            .navigationTitle(Text("Projects", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingCreateProject = true
                    } label: {
                        HStack(spacing: VikuSpacing.xs) {
                            Image(systemName: "plus")
                            Text("New Project", bundle: .module)
                        }
                        .font(VikuFont.subheadline)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .accessibilityIdentifier("projects.create")
                }
            }
            .sheet(isPresented: $isShowingCreateProject, onDismiss: revealCreatedProject) {
                createProjectSheet(parentID: nil)
            }
            .sheet(item: $editingProject, onDismiss: {
                Task { await viewModel.load() }
            }, content: { project in
                EditProjectSheetView(makeViewModel: { makeEditProjectViewModel(project) })
                    .vikuNativeSheetAppearance()
            })
            .sheet(item: $renamingFilterProject, onDismiss: {
                Task { await viewModel.load() }
            }, content: { project in
                RenameFilterSheetView(makeViewModel: { makeRenameFilterViewModel(project) })
                    .vikuNativeSheetAppearance()
            })
            .sheet(item: $subprojectParentProject, onDismiss: revealCreatedProject) { parentProject in
                createProjectSheet(parentID: parentProject.id)
            }
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
            .task { await viewModel.start() }
            .task { await viewModel.observeLocalChanges() }
            .task(id: projectToReveal) {
                guard let request = projectToReveal, let deadline = request.deadline else { return }
                try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                guard !Task.isCancelled, projectToReveal == request else { return }
                projectToReveal = nil
            }
            .task(id: projectToHighlight) {
                guard let id = projectToHighlight else { return }
                if !reduceMotion {
                    // Let the row enter the viewport with its normal background before changing its opacity.
                    try? await Task.sleep(for: .seconds(Self.revealScrollDuration))
                }
                guard !Task.isCancelled, projectToHighlight == id else { return }
                highlightedProjectID = id
                projectToHighlight = nil
            }
            .task(id: highlightedProjectID) {
                guard highlightedProjectID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                highlightedProjectID = nil
            }
            .onDisappear {
                projectToReveal = nil
                projectToHighlight = nil
                highlightedProjectID = nil
            }
    }

    private var projectList: some View {
        ScrollViewReader { proxy in
            let request = projectToReveal
            let revealPath: [EntityID]? = request.flatMap { request in
                guard !request.isExpired, viewModel.displayLoadState == .loaded else { return nil }
                return ProjectNode.revealPath(
                    to: request.id, in: viewModel.rootNodes, isOnline: isOnline, syncStatuses: pendingSyncStatuses,
                )
            }
            let expandedIDs = expandedProjectIDs.union(revealPath?.dropLast() ?? [])
            content(expandedIDs: expandedIDs)
                .onChange(of: revealPath) { _, path in
                    guard let request, request == projectToReveal, !request.isExpired, let path else { return }
                    expandedProjectIDs.formUnion(path.dropLast())
                    projectToReveal = nil
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.revealScrollDuration)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    projectToHighlight = request.id
                }
        }
    }

    private func createProjectSheet(parentID: EntityID?) -> some View {
        CreateProjectSheetView(
            makeViewModel: { makeCreateProjectViewModel(parentID) },
            onCreated: { createdProject = ProjectRevealRequest(project: $0) },
        )
        .vikuNativeSheetAppearance()
    }

    private func revealCreatedProject() {
        guard let createdProject else { return }
        self.createdProject = nil
        projectToReveal = createdProject.isExpired ? nil : createdProject
        Task { await viewModel.load() }
    }

    private func content(expandedIDs: Set<EntityID>) -> some View {
        // Keep the same list across load states to stabilize the large title
        // and keep the list's refresh task alive during reloads.
        List {
            switch viewModel.displayLoadState {
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
                    Task { await viewModel.refresh() }
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
                    projectSection(expandedIDs: expandedIDs)
                }
            }
        }
    }

    private func projectSection(expandedIDs: Set<EntityID>) -> some View {
        let rows = Self.flatten(viewModel.rootNodes, expandedProjectIDs: expandedIDs)
        return Section {
            ForEach(rows) { row in
                let isHighlighted = highlightedProjectID == row.id
                ProjectRow(
                    project: row.node.project,
                    taskSummary: row.node.id.remoteValue.flatMap { viewModel.taskSummaries[$0] },
                    level: row.level,
                    hasChildren: !row.node.children.isEmpty,
                    isExpanded: expandedIDs.contains(row.id),
                    onSelect: { router.push(ProjectsRoute.projectOverview(row.node)) },
                    onToggleExpand: { toggleExpanded(row.id) },
                    onEdit: { editingProject = $0 },
                    onDelete: { projectPendingDelete = row.node },
                    onAddSubproject: { subprojectParentProject = row.node.project },
                )
                .listRowBackground(
                    palette.cardBackground.overlay {
                        Rectangle()
                            .fill(palette.brand)
                            .opacity(isHighlighted ? 0.18 : 0)
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: isHighlighted ? 0.4 : 0.7),
                                value: isHighlighted,
                            )
                    },
                )
            }
            .animation(reduceMotion ? nil : .snappy, value: rows.map(\.id))
        } header: {
            Text("My Projects", bundle: .module)
                .vikuSectionHeader()
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
        withAnimation(reduceMotion ? nil : .snappy) {
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
            if expandedProjectIDs.contains(node.project.displayID) {
                rows += flatten(node.children, level: level + 1, expandedProjectIDs: expandedProjectIDs)
            }
            return rows
        }
    }
}

private struct ProjectRevealRequest: Equatable {
    let id: EntityID
    let deadline: Date?

    init(project: Project) {
        self.id = project.displayID
        self.deadline = project.pendingOnlineCreationAt?.addingTimeInterval(1.5)
    }

    var isExpired: Bool {
        deadline.map { $0 <= .now } ?? false
    }
}

private struct ProjectDisplayRow: Identifiable {
    let node: ProjectNode
    let level: Int
    var id: EntityID {
        node.project.displayID
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

    private var accessibilityID: String {
        switch project.id {
        case let .remote(id): "project.remote.\(id)"
        case let .local(id): "project.local.\(id.uuidString)"
        }
    }

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
                .accessibilityIdentifier("\(accessibilityID).expand")
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
            .accessibilityIdentifier("project.addSubproject")
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
        .accessibilityIdentifier(accessibilityID)
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
