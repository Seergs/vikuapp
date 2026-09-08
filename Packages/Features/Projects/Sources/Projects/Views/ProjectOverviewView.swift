import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// A single project's overview: its subprojects (if any), a status filter,
/// and its own tasks grouped by overdue/pending/completed.
///
/// Takes plain closures for its two further pushes (a subproject, a task)
/// rather than a `Router<ProjectsRoute>` directly: `ProjectsRootView` (its own
/// tab's stack) implements them via `router.push(_:)`, but
/// `ProjectOverviewRootView` (pushed cross-feature from `Features/Tasks`'
/// project pill) has no `Router` of its own — it chains further
/// `.navigationDestination`s onto whatever ambient stack is already hosting
/// it instead. Owning a second `NavigationStack` there to back a `Router`
/// would nest one `NavigationStack` inside another's push destination, which
/// on iOS immediately pops the pushed screen back off.
struct ProjectOverviewView: View {
    @Bindable var viewModel: ProjectOverviewViewModel
    let onSelectSubproject: (ProjectNode) -> Void
    let onSelectTask: (VikunjaTask) -> Void
    let onEditProject: (Project) -> Void
    @State private var filter: ProjectTaskFilter = .all
    @State private var taskPendingDelete: VikunjaTask?
    @State private var taskPendingMove: VikunjaTask?
    @AppStorage("taskSort.field") private var sortField: TaskSort.Field = .dueDate
    @AppStorage("taskSort.direction") private var sortDirection: TaskSort.Direction = .ascending

    private var sort: TaskSort {
        TaskSort(field: sortField, direction: sortDirection)
    }

    var body: some View {
        content
            .projectsListStyle()
            .scrollContentBackground(.hidden)
            .background(VikuColor.Surface.page)
            .refreshable { await viewModel.load() }
            .navigationTitle(viewModel.project.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    TaskSortMenu(field: $sortField, direction: $sortDirection)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onEditProject(viewModel.project)
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .task { await viewModel.load() }
            .onAppear { viewModel.markVisible() }
            .onDisappear { viewModel.markHidden() }
            .confirmationDialog(
                "This permanently deletes the task.",
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
                    Button("Delete Task", role: .destructive) {
                        Task { await viewModel.delete(taskPendingDelete) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $taskPendingMove) { task in
                ProjectPickerSheet(
                    title: "Move to Project",
                    projects: viewModel.allProjects,
                    selectedProjectID: nil,
                    excludingSubtreeOf: viewModel.project.id,
                ) { destination in
                    guard let destination else { return }
                    Task { await viewModel.move(task, to: destination) }
                }
                .task { await viewModel.loadMoveCandidates() }
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
                ProjectOverviewStatusView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Couldn't load this project",
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
            ProjectProgressHeader(project: viewModel.project, tasks: viewModel.tasks)
                .padding(.horizontal, VikuSpacing.md)

            if !viewModel.subprojects.isEmpty {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    HStack(spacing: VikuSpacing.xs) {
                        Text("Subprojects")
                            .fontWeight(.bold)
                        Text("\(viewModel.subprojects.count)")
                            .fontWeight(.regular)
                    }
                    .overviewSectionLabelStyle()
                    .padding(.horizontal, VikuSpacing.md)

                    SubprojectScrollRow(
                        subprojects: viewModel.subprojects,
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

            ProjectTaskFilterRow(selection: $filter)
                .padding(.horizontal, VikuSpacing.md)
        }
        .padding(.vertical, VikuSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)

        let visible = ProjectTaskSection.sections(from: viewModel.tasks, filter: filter, sort: sort)
        if visible.isEmpty {
            ProjectOverviewStatusView(
                systemImage: "checkmark.circle",
                title: viewModel.tasks.isEmpty ? "No tasks yet" : "Nothing here",
                message: viewModel.tasks.isEmpty
                    ? "Tasks in this project will show up here."
                    : "No tasks match this filter.",
                iconSize: 28,
            )
            .padding(.top, VikuSpacing.lg)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(visible) { section in
                HStack(spacing: VikuSpacing.xs) {
                    Text(section.title)
                        .fontWeight(.bold)
                    Text("\(section.tasks.count)")
                        .fontWeight(.regular)
                }
                .overviewSectionLabelStyle()
                .padding(.horizontal, VikuSpacing.md)
                .padding(.top, VikuSpacing.md + VikuSpacing.xs)
                .padding(.bottom, VikuSpacing.sm)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // Each task is its own `List` row (rather than all of them
                // sharing one row inside a `VStack`, as a single card) so a
                // long-press's highlight and `.contextMenu` only ever target
                // the one row under the finger — packed into a shared row,
                // `List` highlights the whole row, i.e. every task in the
                // section at once. The rounded "card" look is recreated by
                // hand across these now-separate rows: only the first row
                // rounds its top corners, only the last rounds its bottom
                // corners, and a manual divider (not `List`'s own, hidden via
                // `.listRowSeparator`) sits between adjacent ones.
                ForEach(Array(section.tasks.enumerated()), id: \.element.id) { index, task in
                    ProjectTaskRow(task: task, projectColor: swatchColor) {
                        Task { await viewModel.toggleDone(task) }
                    } onOpen: {
                        onSelectTask(task)
                    } onMove: {
                        taskPendingMove = task
                    } onDelete: {
                        taskPendingDelete = task
                    }
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.vertical, VikuSpacing.sm)
                    .background(VikuColor.Surface.card)
                    .overlay(alignment: .bottom) {
                        if index < section.tasks.count - 1 {
                            Divider().padding(.leading, VikuSpacing.md)
                        }
                    }
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: index == 0 ? VikuRadius.lg : 0,
                            bottomLeadingRadius: index == section.tasks.count - 1 ? VikuRadius.lg : 0,
                            bottomTrailingRadius: index == section.tasks.count - 1 ? VikuRadius.lg : 0,
                            topTrailingRadius: index == 0 ? VikuRadius.lg : 0,
                            style: .continuous,
                        ),
                    )
                    // Only the card itself gets breathing room from the
                    // screen edges — the label above it stays flush with
                    // the title, matching everything else on this screen.
                    .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var swatchColor: Color {
        Color(vikuHex: viewModel.project.hexColor) ?? VikuColor.brandPrimary
    }
}

/// The project's title (via `.navigationTitle`) is handled by the nav bar;
/// this adds the color swatch + completion count beneath it, matching the
/// design's "■ X/Y tasks completed" subtitle.
private struct ProjectProgressHeader: View {
    let project: Project
    let tasks: [VikunjaTask]

    private var swatchColor: Color {
        Color(vikuHex: project.hexColor) ?? VikuColor.brandPrimary
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatchColor)
                .frame(width: 10, height: 10)

            Text(subtitle)
                .font(VikuFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }

    private var subtitle: String {
        guard !tasks.isEmpty else { return "No tasks yet" }
        let done = tasks.filter(\.isDone).count
        return "\(done)/\(tasks.count) tasks completed"
    }
}

/// Horizontally scrolling cards for this project's direct children, each
/// showing its own task-completion summary (recursively fetched alongside
/// the current project's own tasks — see `ProjectOverviewViewModel.load()`).
private struct SubprojectScrollRow: View {
    let subprojects: [ProjectNode]
    let taskSummaries: [Int: ProjectOverviewViewModel.TaskSummary]
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

    private var swatchColor: Color {
        Color(vikuHex: node.project.hexColor) ?? VikuColor.brandPrimary
    }

    private var summaryText: String {
        guard let taskSummary, taskSummary.total > 0 else { return "No tasks yet" }
        return "\(taskSummary.done)/\(taskSummary.total) tasks"
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

                    Text(summaryText)
                        .font(VikuFont.caption)
                        .foregroundStyle(VikuColor.textTertiary)
                }

                Spacer(minLength: VikuSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
            }
            .padding(VikuSpacing.sm + VikuSpacing.xxs)
            // Fixed (not just minimum) width: the `Spacer` above needs a
            // bounded frame to expand into so the chevron reaches the card's
            // trailing edge — inside a horizontal `ScrollView`, a `Spacer`
            // under only a `minWidth` would try to grow unbounded instead.
            .frame(width: 220, alignment: .leading)
            .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Status filter for this project's own task list.
enum ProjectTaskFilter: CaseIterable {
    case all
    case pending
    case overdue
    case completed

    var title: String {
        switch self {
        case .all: "All"
        case .pending: "Pending"
        case .overdue: "Overdue"
        case .completed: "Completed"
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

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm - VikuSpacing.xxs)
                .foregroundStyle(isSelected ? Color.white : VikuColor.textSecondary)
                .background(
                    Capsule().fill(isSelected ? VikuColor.brandPrimary : VikuColor.Surface.field),
                )
        }
        .buttonStyle(.plain)
    }
}

/// Toolbar menu for choosing the task list's sort field and direction.
/// Backed by `@AppStorage` in the host view, so the choice persists globally
/// across projects and launches.
private struct TaskSortMenu: View {
    @Binding var field: TaskSort.Field
    @Binding var direction: TaskSort.Direction

    var body: some View {
        Menu {
            Picker("Sort By", selection: $field) {
                ForEach(TaskSort.Field.allCases, id: \.self) { field in
                    Text(field.menuTitle).tag(field)
                }
            }
            Picker("Order", selection: $direction) {
                ForEach(TaskSort.Direction.allCases, id: \.self) { direction in
                    Text(direction.menuTitle).tag(direction)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .pickerStyle(.inline)
    }
}

private extension TaskSort.Field {
    var menuTitle: String {
        switch self {
        case .dueDate: "Due Date"
        case .priority: "Priority"
        case .title: "Alphabetical"
        }
    }
}

private extension TaskSort.Direction {
    var menuTitle: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
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

        return [
            overdue.isEmpty ? nil : ProjectTaskSection(title: "Overdue", tasks: sort.sorted(overdue)),
            pending.isEmpty ? nil : ProjectTaskSection(title: "Pending", tasks: sort.sorted(pending)),
            completed.isEmpty ? nil : ProjectTaskSection(title: "Completed", tasks: sort.sorted(completed)),
        ].compactMap(\.self)
    }
}

private struct ProjectTaskRow: View {
    static let labelDisplayLimit = 2

    let task: VikunjaTask
    let projectColor: Color
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    private var isOverdue: Bool {
        guard let dueDate = task.dueDate, !task.isDone else { return false }
        return dueDate < Date()
    }

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
        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Button(action: onToggle) {
                Circle()
                    .strokeBorder(task.isDone ? Color.clear : projectColor, lineWidth: 2)
                    .background(Circle().fill(task.isDone ? projectColor : Color.clear))
                    .frame(width: 24, height: 24)
                    .overlay {
                        if task.isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                Text(task.title)
                    .font(VikuFont.body)
                    .fontWeight(.medium)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? VikuColor.textTertiary : Color.primary)

                HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                    if let dueDate = task.dueDate {
                        Text(DueDateFormatter.compact(dueDate))
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(isOverdue ? VikuColor.Semantic.dangerText : VikuColor.textSecondary)
                    }

                    if task.hasRelations {
                        if task.dueDate == nil {
                            HStack(spacing: VikuSpacing.xxs) {
                                Image(systemName: "link")
                                    .font(.system(size: 11, weight: .regular))
                                Text("Related tasks")
                                    .font(.system(size: 12.5, weight: .regular))
                            }
                            .foregroundStyle(VikuColor.textTertiary)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(VikuColor.textTertiary)
                        }
                    }
                }
                .lineLimit(1)

                if !task.labels.isEmpty {
                    HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                        ForEach(task.labels.prefix(Self.labelDisplayLimit)) { label in
                            LabelPill(label: label)
                        }

                        let remainingLabelCount = task.labels.count - Self.labelDisplayLimit
                        if remainingLabelCount > 0 {
                            ExtraLabelsPill(count: remainingLabelCount)
                        }
                    }
                }
            }

            Spacer(minLength: VikuSpacing.sm)

            if let priorityColor {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, VikuSpacing.xs)
            }
        }
        // The checkbox is its own `Button` above, so a tap landing on it is
        // handled there instead of bubbling up to this one — this only
        // catches taps on the rest of the row (title, due date, labels...).
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Move to Project", systemImage: "folder", action: onMove)
            // `role: .destructive` alone renders blue here, not red: the tab
            // bar's `.tint(VikuColor.brandPrimary)` leaks into the context
            // menu and overrides the role's tint. Pin it back to danger.
            Button("Delete Task", systemImage: "trash", role: .destructive, action: onDelete)
                .tint(VikuColor.Semantic.danger)
        }
    }
}

private struct LabelPill: View {
    let label: VikunjaCore.Label

    private var color: Color {
        Color(vikuHex: label.hexColor) ?? VikuColor.textSecondary
    }

    var body: some View {
        Text(label.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xxs)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct ExtraLabelsPill: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VikuColor.textTertiary)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xxs)
            .background(Capsule().fill(VikuColor.textSecondary.opacity(0.14)))
    }
}

private extension View {
    /// `.plain`, not `.insetGrouped`: `.insetGrouped` always floats its
    /// "card" content in from the screen edges by a fixed system margin,
    /// independent of any `listRowInsets` override — which is exactly what
    /// kept every row on this screen sitting to the right of
    /// `.navigationTitle` no matter how that override was tuned. `.plain`
    /// rows are flush by default, matching the title; `ProjectTaskRow`
    /// recreates the rounded "card" look by hand (per-row corner rounding)
    /// instead of relying on the list style to do it.
    func projectsListStyle() -> some View {
        listStyle(.plain)
    }
}

/// Shared look for the "Subprojects" label and the Overdue/Pending/Completed
/// task-status headers: small, bold, uppercase, and legible against
/// `VikuColor.textSecondary` rather than the system header's faint gray.
private extension View {
    func overviewSectionLabelStyle() -> some View {
        font(VikuFont.footnote)
            .fontWeight(.bold)
            .foregroundStyle(VikuColor.textSecondary)
            .textCase(.uppercase)
            .kerning(0.3)
    }
}

/// Shared empty/error state layout, matching `ProjectsView`'s.
private struct ProjectOverviewStatusView: View {
    let systemImage: String
    let title: String
    let message: String
    var iconSize: CGFloat = 40
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: VikuSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(VikuColor.textTertiary)

            Text(title)
                .font(VikuFont.headline)

            Text(message)
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
                .multilineTextAlignment(.center)

            if let retryAction {
                Button("Try Again", action: retryAction)
                    .buttonStyle(.bordered)
                    .padding(.top, VikuSpacing.xs)
            }
        }
        .padding(VikuSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
