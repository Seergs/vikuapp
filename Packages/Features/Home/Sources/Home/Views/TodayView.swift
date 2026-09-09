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
            Text(pendingSubtitle)
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
                title: datedTaskCount == 0 ? "Nothing due" : "Nothing here",
                message: datedTaskCount == 0
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

    private var datedTaskCount: Int {
        viewModel.tasks.filter { $0.dueDate != nil }.count
    }

    private var pendingSubtitle: String {
        let pending = viewModel.tasks.filter { $0.dueDate != nil && !$0.isDone }.count
        return pending == 1 ? "1 task pending" : "\(pending) tasks pending"
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
    func todayListStyle() -> some View {
        listStyle(.plain)
    }
}
