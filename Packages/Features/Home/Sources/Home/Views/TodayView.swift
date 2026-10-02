import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

/// The Today screen: every project's tasks, grouped by due date into
/// Overdue/Today/Upcoming. Tasks without a due date never appear here — only
/// inside their own project.
struct TodayView: View {
    @Bindable var viewModel: TodayViewModel
    @Environment(AppRouter.self) private var router
    @State private var filter: TodayFilter = .all
    @State private var taskPendingDelete: VikunjaTask?
    @State private var taskPendingMove: VikunjaTask?
    @State private var taskPendingDuplicate: VikunjaTask?
    @State private var taskPendingDueDateEdit: VikunjaTask?
    @State private var taskPendingLabelEdit: VikunjaTask?
    @State private var relationEditStep: RelationEditStep?

    var body: some View {
        content
            .todayListStyle()
            .scrollContentBackground(.hidden)
            .background(VikuColor.Surface.page)
            .refreshable { await viewModel.load() }
            .navigationTitle(Text("Today", bundle: .module))
            .task { await viewModel.load() }
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
            .sheet(item: $taskPendingMove) { task in
                ProjectPickerSheet(
                    title: String(localized: "Move to Project", bundle: .module),
                    projects: viewModel.allProjects,
                    selectedProjectID: nil,
                    excludingSubtreeOf: task.projectID,
                ) { destination in
                    guard let destination else { return }
                    Task { await viewModel.move(task, to: destination) }
                }
                .task { await viewModel.loadMoveCandidates() }
            }
            .sheet(item: $taskPendingDuplicate) { task in
                DuplicateTaskSheetView(
                    makeViewModel: { viewModel.makeDuplicateTaskViewModel(for: task) },
                    onDuplicated: { task, project in
                        router.push(.taskDetail(task, project))
                    },
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
                    title: String(localized: "Couldn't load your tasks", bundle: .module),
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
        // `.plain` list style (see `todayListStyle()`) so every row here is
        // flush with `.navigationTitle` by default — see `ProjectOverviewView`
        // for the same reasoning.
        VStack(alignment: .leading, spacing: VikuSpacing.md) {
            Text(viewModel.pendingSubtitle)
                .font(VikuFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(VikuColor.textSecondary)
                .padding(.horizontal, VikuSpacing.md)

            TodayFilterRow(selection: $filter)
                .padding(.horizontal, VikuSpacing.md)
        }
        .padding(.vertical, VikuSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)

        let visible = TodaySection.sections(from: viewModel.tasks, filter: filter)
        if visible.isEmpty {
            VikuStatusView(
                systemImage: "checkmark.circle",
                title: viewModel.datedTaskCount == 0
                    ? String(localized: "Nothing due", bundle: .module)
                    : String(localized: "Nothing here", bundle: .module),
                message: viewModel.datedTaskCount == 0
                    ? String(localized: "Tasks with a due date will show up here.", bundle: .module)
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
                    let project = viewModel.projectsByID[task.projectID]
                    VikuTaskRow(
                        task: task,
                        project: project,
                        onToggle: { Task { await viewModel.toggleDone(task) } },
                        onOpen: {
                            if let project {
                                router.push(.taskDetail(task, project))
                            }
                        },
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
                            Button(String(localized: "Due Date", bundle: .module), systemImage: "calendar") {
                                taskPendingDueDateEdit = task
                            }
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
                            Button(
                                String(localized: "Delete Task", bundle: .module),
                                systemImage: "trash",
                                role: .destructive,
                            ) {
                                taskPendingDelete = task
                            }
                            .tint(VikuColor.Semantic.danger)
                        },
                    )
                    .vikuCardRow(index: index, count: section.tasks.count)
                }
            }
        }
    }
}

/// Status filter for the Today screen's due-date buckets.
enum TodayFilter: CaseIterable {
    case all
    case overdue
    case today
    case upcoming

    var title: String {
        switch self {
        case .all: String(localized: "All", bundle: .module)
        case .overdue: String(localized: "Overdue", bundle: .module)
        case .today: String(localized: "Today", bundle: .module)
        case .upcoming: String(localized: "Upcoming", bundle: .module)
        }
    }
}

private struct TodayFilterRow: View {
    @Binding var selection: TodayFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VikuSpacing.sm) {
                ForEach(TodayFilter.allCases, id: \.self) { option in
                    TodayFilterChip(title: option.title, isSelected: selection == option) {
                        selection = option
                    }
                }
            }
        }
        // Without this, the first chip sits further right than the row it's
        // in — same nested-ScrollView quirk `ProjectOverviewView` works around.
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}

private struct TodayFilterChip: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(verbatim: title)
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

/// One due-date bucket within the filtered list — Overdue/Today/Upcoming,
/// only showing the ones the current filter and data actually produce.
struct TodaySection: Identifiable {
    let title: String
    let tasks: [VikunjaTask]
    var id: String {
        title
    }

    static func sections(
        from tasks: [VikunjaTask],
        filter: TodayFilter,
        now: Date = Date(),
    ) -> [TodaySection] {
        // Bucketing/sorting lives in `VikunjaCore.TodayDigest` so the Today
        // widget shares the exact same rule; this just maps the buckets the
        // current filter keeps onto titled sections.
        let digest = TodayDigest(tasks: tasks, now: now)

        let overdueTitle = String(localized: "Overdue", bundle: .module)
        let todayTitle = String(localized: "Today", bundle: .module)
        let upcomingTitle = String(localized: "Upcoming", bundle: .module)

        let buckets: [(String, [VikunjaTask])] = switch filter {
        case .all:
            [(overdueTitle, digest.overdue), (todayTitle, digest.today), (upcomingTitle, digest.upcoming)]
        case .overdue:
            [(overdueTitle, digest.overdue)]
        case .today:
            [(todayTitle, digest.today)]
        case .upcoming:
            [(upcomingTitle, digest.upcoming)]
        }

        return buckets.compactMap { title, tasks in
            tasks.isEmpty ? nil : TodaySection(title: title, tasks: tasks)
        }
    }
}

private extension VikunjaTask.Priority {
    /// `displayName` (`VikunjaCore`) is plain English; this screen's priority
    /// menu needs a localized label, so it owns its own translation here
    /// rather than reaching into Core, mirroring `PriorityOption.all` in
    /// `VikuDesignSystem`'s `TaskFormControls.swift`.
    var localizedMenuLabel: String {
        switch self {
        case .unset: String(localized: "None", bundle: .module)
        case .low: String(localized: "Low", bundle: .module)
        case .medium: String(localized: "Medium", bundle: .module)
        case .high: String(localized: "High", bundle: .module)
        case .urgent, .doNow: String(localized: "Urgent", bundle: .module)
        }
    }
}

private extension View {
    /// `.plain`, not `.insetGrouped` — see `ProjectOverviewView.projectsListStyle()`
    /// for why: `.insetGrouped` always floats its content in from the screen
    /// edges by a fixed system margin that can't be tuned away.
    ///
    /// `listRowSpacing(0)` and a zeroed `defaultMinListRowHeight` stop `List`
    /// from adding its own content-independent spacing/height floor on top of
    /// `vikuCardRow`'s own padding — without them the gap between two rows
    /// varied with row content instead of always being exactly that padding.
    /// `listRowSpacing` is iOS-only; this package also builds for macOS to
    /// run its tests.
    @ViewBuilder
    func todayListStyle() -> some View {
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
