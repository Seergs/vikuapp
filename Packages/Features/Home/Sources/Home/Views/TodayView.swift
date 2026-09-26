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
            .navigationTitle("Today")
            .task { await viewModel.load() }
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
                    title: "Couldn't load your tasks",
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
                title: viewModel.datedTaskCount == 0 ? "Nothing due" : "Nothing here",
                message: viewModel.datedTaskCount == 0
                    ? "Tasks with a due date will show up here."
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
                                task.isDone ? "Mark as Not Done" : "Mark as Done",
                                systemImage: task.isDone ? "circle" : "checkmark.circle",
                            ) {
                                Task { await viewModel.toggleDone(task) }
                            }
                            Button("Due Date", systemImage: "calendar") {
                                taskPendingDueDateEdit = task
                            }
                            Menu("Priority", systemImage: "flag") {
                                ForEach(VikunjaTask.Priority.selectable, id: \.self) { priority in
                                    Button {
                                        Task { await viewModel.setPriority(task, to: priority) }
                                    } label: {
                                        HStack {
                                            Text(priority.displayName)
                                            if task.priority == priority {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            Button("Labels", systemImage: "tag") {
                                taskPendingLabelEdit = task
                            }
                            Button("Add Relation", systemImage: "link") {
                                relationEditStep = .pickKind(task)
                            }
                            Button("Duplicate Task", systemImage: "plus.square.on.square") {
                                taskPendingDuplicate = task
                            }
                            Button("Move to Project", systemImage: "folder") {
                                taskPendingMove = task
                            }
                            Button("Delete Task", systemImage: "trash", role: .destructive) {
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
        case .all: "All"
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
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

        let buckets: [(String, [VikunjaTask])] = switch filter {
        case .all:
            [("Overdue", digest.overdue), ("Today", digest.today), ("Upcoming", digest.upcoming)]
        case .overdue:
            [("Overdue", digest.overdue)]
        case .today:
            [("Today", digest.today)]
        case .upcoming:
            [("Upcoming", digest.upcoming)]
        }

        return buckets.compactMap { title, tasks in
            tasks.isEmpty ? nil : TodaySection(title: title, tasks: tasks)
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
