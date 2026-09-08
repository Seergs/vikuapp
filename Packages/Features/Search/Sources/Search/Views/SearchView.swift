import SwiftUI
import VikuDesignSystem
import VikunjaCore

struct SearchView: View {
    @State var viewModel: SearchViewModel
    var onTaskSelected: ((VikunjaTask, Project) -> AnyView)?
    @State private var taskPendingDelete: VikunjaTask?
    @State private var selectedTaskPair: SearchTaskPair?

    var body: some View {
        searchContent
            .task { await viewModel.preload() }
            .animation(.easeInOut(duration: 0.2), value: viewModel.state.value?.map(\.id))
            .searchListStyle()
            .scrollContentBackground(.hidden)
            .background(VikuColor.Surface.page)
            .navigationTitle("Search")
            .navigationDestination(item: $selectedTaskPair) { item in
                if let onTaskSelected {
                    onTaskSelected(item.task, item.project)
                }
            }
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
    }

    private var searchContent: some View {
        List {
            switch viewModel.state {
            case .idle:
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, VikuSpacing.xxl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

            case let .loaded(tasks):
                if tasks.isEmpty {
                    emptySearchResultsState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    loadedContent(tasks)
                }

            case let .failure(message):
                VStack(spacing: VikuSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("Search Error")
                        .font(VikuFont.headline)
                    Text(message)
                        .font(VikuFont.subheadline)
                        .foregroundStyle(VikuColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(VikuSpacing.lg)
                .frame(maxWidth: .infinity)
                .padding(.top, VikuSpacing.lg)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private func loadedContent(_ tasks: [VikunjaTask]) -> some View {
        HStack(spacing: VikuSpacing.xs) {
            Text("RESULTS")
                .fontWeight(.bold)
            Text("\(tasks.count)")
                .fontWeight(.regular)
        }
        .searchSectionLabelStyle()
        .padding(.horizontal, VikuSpacing.md)
        .padding(.top, VikuSpacing.md + VikuSpacing.xs)
        .padding(.bottom, VikuSpacing.sm)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)

        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
            if let project = viewModel.projectsByID[task.projectID] {
                VikuTaskRow(
                    task: task,
                    project: project,
                    onToggle: { Task { await viewModel.toggleDone(task) } },
                    onOpen: {
                        selectedTaskPair = SearchTaskPair(task: task, project: project)
                    },
                    contextMenu: {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            taskPendingDelete = task
                        }
                        .tint(VikuColor.Semantic.danger)
                    },
                )
                .vikuCardRow(index: index, count: tasks.count)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: VikuSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Search Tasks")
                .font(VikuFont.headline)
            Text("Type a query to search all your tasks")
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(VikuSpacing.lg)
    }

    private var emptySearchResultsState: some View {
        VStack(spacing: VikuSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(VikuFont.headline)
            Text("No tasks match your search")
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(VikuSpacing.lg)
    }
}

#Preview {
    NavigationStack {
        SearchView(viewModel: SearchViewModel(
            taskRepository: PreviewTaskRepository(),
            projectRepository: PreviewProjectRepository(),
            toastPresenter: PreviewToastPresenter(),
        ))
    }
}

private struct SearchTaskPair: Identifiable, Hashable {
    let task: VikunjaTask
    let project: Project
    var id: Int {
        task.id
    }
}

private extension View {
    func searchListStyle() -> some View {
        listStyle(.plain)
    }
}

private extension View {
    func searchSectionLabelStyle() -> some View {
        font(VikuFont.footnote)
            .fontWeight(.bold)
            .foregroundStyle(VikuColor.textSecondary)
            .textCase(.uppercase)
            .kerning(0.3)
    }
}

// MARK: - Preview Helpers

private final class PreviewTaskRepository: @unchecked Sendable, TaskRepositoryProtocol {
    func fetchTasks(projectID _: Int) async throws -> [VikunjaTask] {
        []
    }

    func fetchTask(id _: Int) async throws -> VikunjaTask {
        VikunjaTask(id: 0, title: "", projectID: 0)
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func delete(id _: Int) async throws {}
    func searchTasks(query _: String) async throws -> [VikunjaTask] {
        []
    }
}

private final class PreviewProjectRepository: @unchecked Sendable, ProjectRepositoryProtocol {
    func fetchProjects() async throws -> [Project] {
        []
    }

    func fetchProject(id _: Int) async throws -> Project {
        Project(id: 0, title: "")
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id _: Int) async throws {}
}

private final class PreviewToastPresenter: @unchecked Sendable, ToastPresenting {
    func show(_: String, style _: VikunjaCore.ToastStyle) {}
}
