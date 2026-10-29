import Kanban
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// A single project's overview: its subprojects (if any), a status filter,
/// and its own tasks grouped by overdue/pending/completed.
///
/// Takes plain closures for its two further pushes (a subproject, a task)
/// rather than reading `AppRouter` directly: it's the shared component behind
/// both entry points, and each wires the closures to the right route -
/// `ProjectsRootView` pushes a feature-local `ProjectsRoute` (keeping the
/// `ProjectNode` subtree), while `ProjectOverviewRootView` (reached
/// cross-feature) pushes an `AppRoute`.
struct ProjectOverviewView: View {
    @Bindable var viewModel: ProjectOverviewViewModel
    /// Built by the caller (mirrors `viewModel` itself) rather than via a
    /// factory closure held in `@State` here — a `.navigationDestination`
    /// closure further up re-invokes on unrelated re-renders, so the one
    /// place that's safe to build this exactly once is where `viewModel`
    /// itself is already stabilized (`ProjectsRootView`'s cache,
    /// `AppDestinations.swift`'s `ProjectOverviewDestination`).
    let kanbanViewModel: KanbanBoardViewModel
    let onSelectSubproject: (ProjectNode) -> Void
    let onSelectTask: (VikunjaTask) -> Void
    let onEditProject: (Project) -> Void
    /// Called with the duplicate and its (possibly different) project right
    /// before the sheet dismisses, so the caller can push its detail screen —
    /// mirrors `onSelectTask`, but takes the project explicitly since the
    /// duplicate can land in any project the sheet's picker offers, not just
    /// this one.
    let onDuplicated: (VikunjaTask, Project) -> Void
    /// Builds the "create subproject" sheet's view model, taking the parent
    /// project id — mirrors `ProjectsView`/`ProjectsRootView`'s own
    /// `makeCreateProjectViewModel`, reused here with this screen's project
    /// passed as the parent instead of `nil`.
    let makeCreateProjectViewModel: (EntityID?) -> CreateProjectViewModel
    @State private var displayMode: ProjectDisplayMode = .list
    @State private var filter: ProjectTaskFilter = .all
    @State private var searchText = ""
    @State private var taskPendingDelete: VikunjaTask?
    @State private var taskPendingMove: VikunjaTask?
    @State private var taskPendingDuplicate: VikunjaTask?
    @State private var taskPendingDueDateEdit: VikunjaTask?
    @State private var taskPendingLabelEdit: VikunjaTask?
    @State private var relationEditStep: RelationEditStep?
    @State private var isShowingCreateSubproject = false
    @State private var isShowingDeleteProjectConfirmation = false
    @Environment(\.vikuPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var sort: TaskSort {
        TaskSort(field: viewModel.sortField, direction: viewModel.sortDirection)
    }

    /// `viewModel.tasks` narrowed to the in-flight search text, by title only
    /// — local filtering over whatever's already loaded, not a server
    /// round-trip (that's what the global Search tab is for).
    private var filteredTasks: [VikunjaTask] {
        guard !searchText.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter { $0.title.localizedStandardContains(searchText) }
    }

    /// Pulled out of `body` (which was timing out the type checker once this
    /// screen's modifier chain got long enough) rather than for its own sake.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.supportsKanban {
            // Pops in once the capability check resolves rather than
            // fading, on every SwiftUI version tried — content inside a
            // `ToolbarItem` is hosted through the bridge to
            // `UINavigationBar` and doesn't reliably honor `.transition`/
            // `.animation`, including when the item itself is kept
            // structurally present and only its inner content is
            // conditional. Accepted as a platform limitation rather than
            // chased further.
            ToolbarItem(placement: .primaryAction) {
                DisplayModeSwitcher(selection: $displayMode)
            }
            .hidingSharedGlassBackground
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ProjectOverviewMenuContent(
                    sortField: $viewModel.sortField,
                    sortDirection: $viewModel.sortDirection,
                    kind: viewModel.project.kind,
                    onEditProject: { onEditProject(viewModel.project) },
                    onAddSubproject: { isShowingCreateSubproject = true },
                    onDeleteProject: { isShowingDeleteProjectConfirmation = true },
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// Split out of `body`, which was timing out the type checker once this
    /// screen's modifier chain got long enough — this half carries the
    /// navigation chrome (title, search, toolbar); `body` applies the rest
    /// (lifecycle hooks, sheets, confirmations) on top of it, so the type
    /// checker sees two shorter expressions instead of one very long one.
    private var screenChrome: some View {
        VStack(spacing: 0) {
            switch displayMode {
            case .list:
                content
                    .projectsListStyle()
                    .scrollContentBackground(.hidden)
                    .refreshable { await viewModel.load() }
            case .kanban:
                KanbanBoardView(viewModel: kanbanViewModel, searchText: searchText, onSelectTask: onSelectTask)
            }
        }
        .background(palette.pageBackground)
        .navigationTitle(viewModel.project.title)
        .searchable(text: $searchText, prompt: Text("Search tasks", bundle: .module))
        .toolbar { toolbarContent }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isOffline)
    }

    var body: some View {
        screenChrome
            .task {
                await viewModel.load()
            }
            .task {
                await viewModel.observeReachability()
            }
            .onAppear {
                viewModel.markVisible()
            }
            .onDisappear { viewModel.markHidden() }
            .onChange(of: viewModel.lastCreatedTaskForThisProject) { _, event in
                guard event != nil else { return }
                Task { await viewModel.load() }
            }
            .confirmationDialog(
                Text("This permanently deletes the task.", bundle: .module),
                isPresented: Binding(
                    get: { taskPendingDelete != nil },
                    set: { isPresented in
                        if !isPresented {
                            taskPendingDelete = nil
                        }
                    },
                ),
                titleVisibility: .visible,
            ) {
                if let taskPendingDelete {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(taskPendingDelete) }
                    } label: {
                        Text("Delete Task", bundle: .module)
                    }
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            }
            .confirmationDialog(
                Text(verbatim: deleteProjectConfirmationMessage),
                isPresented: $isShowingDeleteProjectConfirmation,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) {
                    Task {
                        if await viewModel.deleteProject() {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.project.kind == .savedFilter {
                        Text("Delete Filter", bundle: .module)
                    } else {
                        Text("Delete Project", bundle: .module)
                    }
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            }
            .sheet(isPresented: $isShowingCreateSubproject) {
                CreateProjectSheetView(
                    makeViewModel: { makeCreateProjectViewModel(viewModel.project.id) },
                    onCreated: { viewModel.addSubproject($0) },
                )
            }
            .sheet(item: $taskPendingMove) { task in
                ProjectPickerSheet(
                    title: String(localized: "Move to Project", bundle: .module),
                    projects: viewModel.allProjects,
                    selectedProjectID: nil,
                    excludingSubtreeOf: viewModel.project.id,
                ) { destination in
                    guard let destination else { return }
                    Task { await viewModel.move(task, to: destination) }
                }
                .task { await viewModel.loadMoveCandidates() }
            }
            .sheet(item: $taskPendingDuplicate) { task in
                DuplicateTaskSheetView(
                    makeViewModel: { viewModel.makeDuplicateTaskViewModel(for: task) },
                    onDuplicated: onDuplicated,
                )
            }
            .sheet(item: $taskPendingDueDateEdit) { task in
                DueDatePickerSheet(initialDate: task.dueDate) { newDate in
                    Task { await viewModel.setDueDate(task, to: newDate) }
                }
            }
            .sheet(item: $taskPendingLabelEdit) { task in
                LabelPickerSheet(
                    taskLabels: viewModel.tasks.first(where: { $0.id == task.id })?.labels ?? task.labels,
                    allLabels: viewModel.allLabels,
                    onLoad: { await viewModel.loadAllLabels() },
                    onToggle: { label in Task { await viewModel.toggleLabel(task, label) } },
                    onCreate: { title, hexColor in
                        Task { await viewModel.createAndAddLabel(task, title: title, hexColor: hexColor) }
                    },
                )
            }
            .sheet(item: $relationEditStep) { step in
                switch step {
                case let .pickKind(task):
                    RelationKindPickerSheet { kind in
                        relationEditStep = .pickTask(task, kind)
                    }
                case let .pickTask(task, kind):
                    RelationTaskPickerSheet(
                        kind: kind,
                        results: viewModel.relationSearchResults,
                        projectTitle: { candidate in
                            viewModel.allProjects.first { $0.id == candidate.projectID }?.title
                        },
                        onAppear: {
                            await viewModel.loadMoveCandidates()
                            await viewModel.loadRelationSuggestions(for: task)
                        },
                        onSearch: { query in await viewModel.searchTasksForRelation(for: task, query: query) },
                        onSelect: { candidate in
                            let relation = TaskRelation(
                                id: candidate.id, title: candidate.title,
                                isDone: candidate.isDone, projectID: candidate.projectID,
                            )
                            Task { await viewModel.addRelation(relation, kind: kind, to: task) }
                            relationEditStep = nil
                        },
                    )
                }
            }
    }

    /// Mirrors `ProjectsView.deleteConfirmationMessage`: this screen's own
    /// `subprojects` (direct children only) stand in for `ProjectNode.children`.
    private var deleteProjectConfirmationMessage: String {
        if viewModel.project.kind == .savedFilter {
            return String(localized: "This permanently deletes the saved filter.", bundle: .module)
        }
        return viewModel.subprojects.isEmpty
            ? String(localized: "This permanently deletes the project and all its tasks.", bundle: .module)
            : String(
                localized: "This permanently deletes the project, its subprojects, and all their tasks.",
                bundle: .module,
            )
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
                    title: String(localized: "Couldn't load this project", bundle: .module),
                    message: message,
                ) {
                    Task { await viewModel.load() }
                }
                .padding(.top, VikuSpacing.xxl)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            case .loaded:
                loadedContent
            }
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        // `.plain` list style (see `projectsListStyle()`) so every row here
        // is flush with `.navigationTitle` by default, with `EdgeInsets()`
        // to strip even the small residual default `.plain` gives rows —
        // our own `.padding(.horizontal, VikuSpacing.md)` inside each
        // piece below is the only horizontal offset left, so it can't stack
        // with a system default the way it did under `.insetGrouped`.
        VStack(alignment: .leading, spacing: VikuSpacing.md) {
            if viewModel.project.kind == .savedFilter {
                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    VikuSavedFilterBadge()

                    if let query = viewModel.savedFilterQuery {
                        SavedFilterQueryLine(query: query)
                    }
                }
                .padding(.horizontal, VikuSpacing.md)
                if viewModel.isOffline {
                    SavedFilterOfflineNotice()
                        .padding(.horizontal, VikuSpacing.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else if viewModel.project.kind == .favorites {
                VikuFavoritesBadge()
                    .padding(.horizontal, VikuSpacing.md)
            }

            ProjectProgressHeader(project: viewModel.project, tasks: viewModel.tasks)
                .padding(.horizontal, VikuSpacing.md)

            // Favorites and saved filters are pseudo-projects with no row in
            // the real `projects` table, so they can't own a subproject —
            // the whole block (button or list) is hidden rather than
            // offering an "Add Subproject" that would fail server-side.
            if viewModel.project.kind == .project {
                let visibleSubprojects = viewModel.subprojectsWithPendingTasks
                if viewModel.subprojects.isEmpty {
                    AddSubprojectButton { isShowingCreateSubproject = true }
                        .padding(.horizontal, VikuSpacing.md)
                        .padding(.top, VikuSpacing.xs)
                } else if !visibleSubprojects.isEmpty {
                    VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                        HStack(spacing: VikuSpacing.xs) {
                            Text("Subprojects", bundle: .module)
                                .fontWeight(.bold)
                            Text(verbatim: "\(visibleSubprojects.count)")
                                .fontWeight(.regular)
                        }
                        .vikuSectionHeader()
                        .padding(.horizontal, VikuSpacing.md)

                        SubprojectScrollRow(
                            subprojects: visibleSubprojects,
                            taskSummaries: viewModel.subprojectTaskSummaries,
                        ) { subproject in
                            onSelectSubproject(subproject)
                        }
                        .padding(.horizontal, VikuSpacing.md)
                    }
                    // A bit more than the parent `VStack`'s own spacing, just
                    // for the gap after "X/Y tasks completed" specifically.
                    .padding(.top, VikuSpacing.xs)
                }
                // Else: this project has subprojects, but none with pending
                // tasks (all brand new or all completed) — hide the block
                // entirely, including the "Add Subproject" button, rather
                // than showing an empty "Subprojects" row.
            }

            ProjectTaskFilterRow(selection: $filter)
                .padding(.horizontal, VikuSpacing.md)
        }
        .padding(.vertical, VikuSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)

        let visible = ProjectTaskSection.sections(from: filteredTasks, filter: filter, sort: sort)
        if visible.isEmpty {
            VikuStatusView(
                systemImage: "checkmark.circle",
                title: viewModel.tasks.isEmpty
                    ? String(localized: "No tasks yet", bundle: .module)
                    : String(localized: "Nothing here", bundle: .module),
                message: viewModel.tasks.isEmpty
                    ? String(localized: "Tasks in this project will show up here.", bundle: .module)
                    : String(localized: "No tasks match this filter.", bundle: .module),
                iconSize: 28,
            )
            .padding(.top, VikuSpacing.lg)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(visible) { section in
                HStack(spacing: VikuSpacing.xs) {
                    Text(verbatim: section.title)
                        .fontWeight(.bold)
                    Text(verbatim: "\(section.tasks.count)")
                        .fontWeight(.regular)
                }
                .vikuSectionHeader()
                .padding(.horizontal, VikuSpacing.md)
                .padding(.top, VikuSpacing.md + VikuSpacing.xs)
                .padding(.bottom, VikuSpacing.sm)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(Array(section.tasks.enumerated()), id: \.element.id) { index, task in
                    // `showsProjectBadge: false` — the project is already this
                    // screen's navigation title, so the row only needs its
                    // color for the checkbox tint.
                    VikuTaskRow(
                        task: task,
                        project: viewModel.project,
                        showsProjectBadge: false,
                        onToggle: { Task { await viewModel.toggleDone(task) } },
                        onOpen: { onSelectTask(task) },
                        contextMenu: {
                            Button(
                                task.isDone
                                    ? String(localized: "Mark as Not Done", bundle: .module)
                                    : String(localized: "Mark as Done", bundle: .module),
                                systemImage: task.isDone ? "circle" : "checkmark.circle",
                            ) {
                                Task { await viewModel.toggleDone(task) }
                            }
                            Divider()
                            DueDateMenu(
                                currentDueDate: task.dueDate,
                                onSelect: { date in Task { await viewModel.setDueDate(task, to: date) } },
                                onCustom: { taskPendingDueDateEdit = task },
                            )
                            Menu(String(localized: "Priority", bundle: .module), systemImage: "flag") {
                                ForEach(VikunjaTask.Priority.selectable, id: \.self) { priority in
                                    Button {
                                        Task { await viewModel.setPriority(task, to: priority) }
                                    } label: {
                                        HStack {
                                            Text(verbatim: priority.localizedMenuLabel)
                                            if task.priority == priority {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            Button(String(localized: "Labels", bundle: .module), systemImage: "tag") {
                                taskPendingLabelEdit = task
                            }
                            Divider()
                            Button(String(localized: "Add Relation", bundle: .module), systemImage: "link") {
                                relationEditStep = .pickKind(task)
                            }
                            Button(
                                String(localized: "Duplicate Task", bundle: .module),
                                systemImage: "plus.square.on.square",
                            ) {
                                taskPendingDuplicate = task
                            }
                            Button(String(localized: "Move to Project", bundle: .module), systemImage: "folder") {
                                taskPendingMove = task
                            }
                            Divider()
                            // `role: .destructive` alone renders blue here: the
                            // tab bar's tint leaks into the context menu and
                            // overrides it. Pin it back to danger.
                            Button(
                                String(localized: "Delete Task", bundle: .module),
                                systemImage: "trash",
                                role: .destructive,
                            ) {
                                taskPendingDelete = task
                            }
                            .tint(palette.semanticDanger)
                        },
                    )
                    .vikuCardRow(index: index, count: section.tasks.count)
                }
            }
        }
    }
}

/// The project's title (via `.navigationTitle`) is handled by the nav bar;
/// this adds the color swatch + completion count beneath it, matching the
/// design's "■ X/Y tasks completed" subtitle.
private struct ProjectProgressHeader: View {
    let project: Project
    let tasks: [VikunjaTask]

    @Environment(\.vikuPalette) private var palette

    private var swatchColor: Color {
        Color(vikuHex: project.hexColor) ?? palette.brand
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatchColor)
                .frame(width: 10, height: 10)

            Text(verbatim: subtitle)
                .font(VikuFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var subtitle: String {
        guard !tasks.isEmpty else { return String(localized: "No tasks yet", bundle: .module) }
        let done = tasks.filter(\.isDone).count
        return String(localized: "\(done)/\(tasks.count) tasks completed", bundle: .module)
    }
}

/// Horizontally scrolling cards for this project's direct children, each
/// showing its own task-completion summary (recursively fetched alongside
/// the current project's own tasks — see `ProjectOverviewViewModel.load()`).
private struct SubprojectScrollRow: View {
    let subprojects: [ProjectNode]
    let taskSummaries: [EntityID: ProjectOverviewViewModel.TaskSummary]
    let onSelect: (ProjectNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VikuSpacing.sm) {
                ForEach(subprojects) { node in
                    SubprojectCard(node: node, taskSummary: taskSummaries[node.id]) { onSelect(node) }
                }
            }
        }
        // Nested inside a `List` row, a horizontal `ScrollView` otherwise
        // inherits an automatic leading content margin from its ancestors —
        // zeroing it here is what makes the first card start exactly where
        // the row itself starts, instead of a bit further right.
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}

private struct SubprojectCard: View {
    let node: ProjectNode
    let taskSummary: ProjectOverviewViewModel.TaskSummary?
    let onSelect: () -> Void

    @Environment(\.vikuPalette) private var palette
    @Environment(\.pendingSyncStatuses) private var pendingSyncStatuses

    private var swatchColor: Color {
        Color(vikuHex: node.project.hexColor) ?? palette.brand
    }

    private var syncStatus: SyncItemStatus? {
        pendingSyncStatuses[SyncItemKey(kind: .project, id: node.project.id)]
    }

    private var summaryText: String {
        guard let taskSummary, taskSummary.total > 0 else {
            return String(localized: "No tasks yet", bundle: .module)
        }
        return String(localized: "\(taskSummary.done)/\(taskSummary.total) tasks", bundle: .module)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: VikuSpacing.sm) {
                RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous)
                    .fill(swatchColor.opacity(0.16))
                    .frame(width: 36, height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(swatchColor)
                            .frame(width: 12, height: 12)
                    }

                VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                    Text(node.project.title)
                        .font(VikuFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(verbatim: summaryText)
                        .font(VikuFont.caption)
                        .foregroundStyle(palette.textTertiary)
                }

                Spacer(minLength: VikuSpacing.xs)

                if let syncStatus {
                    VikuPendingSyncIndicator(status: syncStatus)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(VikuSpacing.sm + VikuSpacing.xxs)
            // Fixed (not just minimum) width: the `Spacer` above needs a
            // bounded frame to expand into so the chevron reaches the card's
            // trailing edge — inside a horizontal `ScrollView`, a `Spacer`
            // under only a `minWidth` would try to grow unbounded instead.
            .frame(width: 220, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The empty-state affordance shown where the "Subprojects" row would
/// otherwise go, once this project has at least one child: a plain,
/// left-aligned, borderless link rather than a boxed call-to-action.
private struct AddSubprojectButton: View {
    let action: () -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add Subproject", bundle: .module)
                    .font(VikuFont.footnote)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(palette.brand)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Which body `ProjectOverviewView` currently shows — the existing task
/// `List`, or the Kanban board (gated on `viewModel.supportsKanban`).
enum ProjectDisplayMode: Hashable {
    case list
    case kanban
}

/// Status filter for this project's own task list.
enum ProjectTaskFilter: CaseIterable {
    case all
    case pending
    case overdue
    case completed

    var title: String {
        switch self {
        case .all: String(localized: "All", bundle: .module)
        case .pending: String(localized: "Pending", bundle: .module)
        case .overdue: String(localized: "Overdue", bundle: .module)
        case .completed: String(localized: "Completed", bundle: .module)
        }
    }
}

private struct ProjectTaskFilterRow: View {
    @Binding var selection: ProjectTaskFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VikuSpacing.sm) {
                ForEach(ProjectTaskFilter.allCases, id: \.self) { option in
                    FilterChip(title: option.title, isSelected: selection == option) {
                        selection = option
                    }
                }
            }
        }
        // See `SubprojectScrollRow`: without this, the first chip sits
        // further right than the row it's in.
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        Button(action: onSelect) {
            Text(verbatim: title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm - VikuSpacing.xxs)
                .foregroundStyle(isSelected ? palette.brandForeground : palette.textSecondary)
                .background(
                    Capsule().fill(isSelected ? palette.brand : palette.fieldBackground),
                )
        }
        .buttonStyle(.plain)
    }
}

/// The saved filter's raw query, own line below the "Matches" label so it
/// gets the full row width (less truncation than sharing a line with the
/// label) - starts truncated to one line, tap to expand into a full wrap for
/// the rare query long enough to still get cut off. The query itself renders
/// `.verbatim` - it's Vikunja's own filter syntax
/// (https://vikunja.io/docs/filters), not natural-language UI copy, so it's
/// never localized. The label stays small and muted (just chrome); the query
/// is the actual content, so it gets more contrast and a monospace font to
/// read as data rather than a continuation of the label's sentence.
private struct SavedFilterQueryLine: View {
    let query: String
    @State private var isExpanded = false

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
            Text("Matches", bundle: .module)
                .font(.caption2)
                .foregroundStyle(palette.textTertiary)

            Text(verbatim: query)
                .font(VikuFont.caption.monospaced())
                .foregroundStyle(palette.textSecondary)
                .lineLimit(isExpanded ? nil : 1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Toolbar menu for choosing the task list's sort field and direction.
/// Backed by `@AppStorage` in the host view, so the choice persists globally
/// across projects and launches.
/// The combined "..." overflow menu's contents: sort field, sort direction,
/// then the project edit action — everything that used to be a separate
/// sort-icon menu plus a standalone pencil button, freed up so the toolbar
/// has room for `DisplayModeSwitcher`.
private struct ProjectOverviewMenuContent: View {
    @Binding var sortField: TaskSort.Field
    @Binding var sortDirection: TaskSort.Direction
    let kind: ProjectKind
    let onEditProject: () -> Void
    let onAddSubproject: () -> Void
    let onDeleteProject: () -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        // A `Section("Sort") { Picker; Picker }` silently drops its header
        // here — a `Section` in a `Menu` only reliably shows a title when its
        // content includes a plain item like a `Button`; a section made up
        // entirely of `Picker`s doesn't render one (see "Project" below,
        // which does). A nested `Menu` always shows its own label, so this
        // sidesteps that rather than fighting it.
        Menu(String(localized: "Sort", bundle: .module), systemImage: "arrow.up.arrow.down") {
            Picker(String(localized: "Sort By", bundle: .module), selection: $sortField) {
                ForEach(TaskSort.Field.allCases, id: \.self) { field in
                    Text(verbatim: field.menuTitle).tag(field)
                }
            }
            Picker(String(localized: "Order", bundle: .module), selection: $sortDirection) {
                ForEach(TaskSort.Direction.allCases, id: \.self) { direction in
                    Text(verbatim: direction.menuTitle).tag(direction)
                }
            }
        }
        // Favorites is a fixed pseudo-list with no row of its own on the
        // server - nothing here applies to it, so the whole section is left
        // out rather than showing empty. A saved filter is a real
        // server-side resource (can be renamed/deleted) but, like Favorites,
        // can't own a subproject - see "Add Subproject" below.
        if kind != .favorites {
            Section(String(localized: "Project", bundle: .module)) {
                Button(editTitle, systemImage: "pencil", action: onEditProject)
                if kind == .project {
                    Button(
                        String(localized: "Add Subproject", bundle: .module),
                        systemImage: "folder.badge.plus",
                        action: onAddSubproject,
                    )
                }
                // `role: .destructive` alone renders blue here: the tab bar's
                // tint leaks into the context menu and overrides it, same as
                // the per-task "Delete Task" button on this screen's rows.
                Button(deleteTitle, systemImage: "trash", role: .destructive, action: onDeleteProject)
                    .tint(palette.semanticDanger)
            }
        }
    }

    private var editTitle: String {
        kind == .savedFilter
            ? String(localized: "Rename Filter", bundle: .module)
            : String(localized: "Edit Project", bundle: .module)
    }

    private var deleteTitle: String {
        kind == .savedFilter
            ? String(localized: "Delete Filter", bundle: .module)
            : String(localized: "Delete Project", bundle: .module)
    }
}

private extension ToolbarContent {
    /// iOS 26 wraps every `ToolbarItem`'s content in a shared Liquid Glass
    /// background the system draws automatically. That's the right look for
    /// a plain icon or label, but `DisplayModeSwitcher` paints its own opaque
    /// capsule in theme colors — the system's glass then composites over/
    /// behind it and dilutes those colors toward a neutral glass tint. Only
    /// visible on real-device compositing (the Simulator renders Liquid
    /// Glass flatter) and only for this item: this toolbar's other items
    /// (the nav title, the "..." menu icon) have no custom background of
    /// their own to compete with the glass. Hiding the shared background
    /// here lets this capsule render as drawn instead.
    @ToolbarContentBuilder
    var hidingSharedGlassBackground: some ToolbarContent {
        if #available(iOS 26, macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// A capsule-shaped List/Kanban switch: the selected side shows its icon and
/// title on a raised background, the other collapses to just its icon —
/// mirrors the product mockup's `ViewSwitcher` rather than a native
/// `.pickerStyle(.segmented)`, which always renders every segment the same
/// way and can't collapse the unselected one.
private struct DisplayModeSwitcher: View {
    @Binding var selection: ProjectDisplayMode
    @Namespace private var namespace
    @Environment(\.vikuPalette) private var palette

    private struct Option {
        let mode: ProjectDisplayMode
        let title: String
        let systemImage: String
    }

    private static let options: [Option] = [
        Option(mode: .list, title: String(localized: "List", bundle: .module), systemImage: "list.bullet"),
        Option(mode: .kanban, title: String(localized: "Kanban", bundle: .module), systemImage: "rectangle.split.3x1"),
    ]

    var body: some View {
        HStack(spacing: VikuSpacing.xxs) {
            ForEach(Self.options, id: \.mode) { option in
                segment(for: option)
            }
        }
        .padding(VikuSpacing.xxs)
        .background(palette.fieldBackground, in: Capsule())
        // A toolbar item otherwise proposes a width tight enough to clip
        // this view's `Text` down to its first letter — forces SwiftUI to
        // lay it out, and the toolbar to size it, at its natural width.
        .fixedSize()
        // Scoped to this view's own layout (the sliding pill, the
        // icon-only/icon+label collapse) rather than wrapping the
        // `selection` write itself in `withAnimation` - that would also
        // animate `ProjectOverviewView`'s List/KanbanBoardView swap one
        // level up, which is what produced the nav-title flicker: SwiftUI
        // tried to cross-fade two structurally unrelated view hierarchies
        // under one bar.
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)
    }

    private func segment(for option: Option) -> some View {
        let isSelected = selection == option.mode
        return Button {
            selection = option.mode
        } label: {
            HStack(spacing: VikuSpacing.xs) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                // Always present (never inserted/removed) so SwiftUI
                // interpolates its width and opacity as one continuous
                // animation instead of popping it in/out, which is what read
                // as laggy — an insert/remove transition doesn't blend with
                // the sibling icon's position shifting at the same time.
                Text(verbatim: option.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: isSelected ? nil : 0, alignment: .leading)
                    .opacity(isSelected ? 1 : 0)
                    .clipped()
            }
            // `palette.textPrimary` rather than `Color.primary`: this view
            // sits inside a `ToolbarItem`, and `Color.primary`'s hierarchical
            // style gets an automatic vibrancy blend against iOS 26's Liquid
            // Glass toolbar background, washing it out on real-device
            // compositing for the custom dark themes (Solarized, Cyberpunk,
            // Terminal, Vaporwave) — invisible in the Simulator, which
            // renders Liquid Glass flatter. See `VikuPalette.textPrimary`.
            .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
            .padding(.horizontal, isSelected ? VikuSpacing.sm + VikuSpacing.xxs : VikuSpacing.sm)
            .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
            .background {
                if isSelected {
                    Capsule()
                        .fill(palette.cardBackground)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private extension TaskSort.Field {
    var menuTitle: String {
        switch self {
        case .dueDate: String(localized: "Due Date", bundle: .module)
        case .priority: String(localized: "Priority", bundle: .module)
        case .title: String(localized: "Alphabetical", bundle: .module)
        }
    }
}

private extension TaskSort.Direction {
    var menuTitle: String {
        switch self {
        case .ascending: String(localized: "Ascending", bundle: .module)
        case .descending: String(localized: "Descending", bundle: .module)
        }
    }
}

/// One status grouping of tasks within the filtered list — mirrors the
/// design's "Overdue" / "Pending" / "Completed" sections, only showing the
/// ones the current filter and data actually produce.
private struct ProjectTaskSection: Identifiable {
    let title: String
    let tasks: [VikunjaTask]
    var id: String {
        title
    }

    static func sections(
        from tasks: [VikunjaTask],
        filter: ProjectTaskFilter,
        sort: TaskSort,
    ) -> [ProjectTaskSection] {
        let now = Date()
        func isOverdue(_ task: VikunjaTask) -> Bool {
            guard let dueDate = task.dueDate, !task.isDone else { return false }
            return dueDate < now
        }

        let filtered: [VikunjaTask] = switch filter {
        case .all: tasks
        case .pending: tasks.filter { !$0.isDone }
        case .overdue: tasks.filter(isOverdue)
        case .completed: tasks.filter(\.isDone)
        }

        let overdue = filtered.filter(isOverdue)
        let pending = filtered.filter { !$0.isDone && !isOverdue($0) }
        let completed = filtered.filter(\.isDone)

        let overdueTitle = String(localized: "Overdue", bundle: .module)
        let pendingTitle = String(localized: "Pending", bundle: .module)
        let completedTitle = String(localized: "Completed", bundle: .module)

        return [
            overdue.isEmpty ? nil : ProjectTaskSection(title: overdueTitle, tasks: sort.sorted(overdue)),
            pending.isEmpty ? nil : ProjectTaskSection(title: pendingTitle, tasks: sort.sorted(pending)),
            completed.isEmpty ? nil : ProjectTaskSection(title: completedTitle, tasks: sort.sorted(completed)),
        ].compactMap(\.self)
    }
}

private extension VikunjaTask.Priority {
    /// `displayName` (`VikunjaCore`) is plain English; this screen's priority
    /// menu needs a localized label, so it owns its own translation here
    /// rather than reaching into Core, mirroring `PriorityOption.all` in
    /// `VikuDesignSystem`'s `TaskFormControls.swift` and `Home`'s `TodayView`.
    var localizedMenuLabel: String {
        switch self {
        // Distinct key from `ParentProjectField`'s "None" (`CreateProjectSheetView`/
        // `EditProjectSheetView`): that one agrees with "proyecto" (masculine,
        // "Ninguno"), this one with "prioridad" (feminine, "Ninguna") — same
        // English source text, different Spanish translations.
        case .unset: String(localized: "priority.none", defaultValue: "None", bundle: .module)
        case .low: String(localized: "Low", bundle: .module)
        case .medium: String(localized: "Medium", bundle: .module)
        case .high: String(localized: "High", bundle: .module)
        case .urgent, .doNow: String(localized: "Urgent", bundle: .module)
        }
    }
}

private extension View {
    /// `.plain`, not `.insetGrouped`: `.insetGrouped` always floats its
    /// "card" content in from the screen edges by a fixed system margin,
    /// independent of any `listRowInsets` override — which is exactly what
    /// kept every row on this screen sitting to the right of
    /// `.navigationTitle` no matter how that override was tuned. `.plain`
    /// rows are flush by default, matching the title; `.vikuCardRow(index:count:)`
    /// recreates the rounded "card" look by hand (per-row corner rounding)
    /// instead of relying on the list style to do it.
    ///
    /// See `TodayView.todayListStyle()` for why `listRowSpacing(0)` and a
    /// zeroed `defaultMinListRowHeight` are needed alongside `.plain`, and
    /// why `listRowSpacing` is gated to iOS.
    @ViewBuilder
    func projectsListStyle() -> some View {
        #if os(iOS)
        listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
        #else
        listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
        #endif
    }
}

private struct SavedFilterOfflineNotice: View {
    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 1)
            Text(
                "Offline: tasks might not appear or disappear from this filter until you reconnect.",
                bundle: .module,
            )
            .font(VikuFont.footnote)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VikuSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.fieldBackground,
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}
