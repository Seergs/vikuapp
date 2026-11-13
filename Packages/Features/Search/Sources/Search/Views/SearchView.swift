import Foundation
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taskPendingDelete: VikunjaTask?
    @State private var spinnerShownAt: ContinuousClock.Instant?

    var body: some View {
        searchContent
            .task { await viewModel.preload() }
            .task(id: viewModel.state.isLoading) { await updateSpinner() }
            .onDisappear {
                viewModel.cancelSearch()
                spinnerShownAt = nil
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.state.value?.map(\.id))
            .searchListStyle()
            .scrollContentBackground(.hidden)
            .background(palette.pageBackground)
            .searchable(
                text: $viewModel.query,
                placement: .automatic,
                prompt: Text("Search tasks", bundle: .module),
            )
            .onChange(of: viewModel.query) { _, _ in
                viewModel.queryChanged()
            }
            .onChange(of: viewModel.syntax) { _, _ in
                viewModel.queryChanged()
            }
            .navigationTitle(Text("Search", bundle: .module))
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
    }

    private var searchContent: some View {
        List {
            if spinnerShownAt != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, VikuSpacing.xxl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                resultContent
            }
        }
    }

    /// Presentation timing never delays the repository query or its result state.
    private func updateSpinner() async {
        do {
            if viewModel.state.isLoading {
                guard spinnerShownAt == nil else { return }
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, viewModel.state.isLoading else { return }
                spinnerShownAt = .now
            } else if let spinnerShownAt {
                try await ContinuousClock().sleep(until: spinnerShownAt.advanced(by: .seconds(1)))
                guard !Task.isCancelled else { return }
                self.spinnerShownAt = nil
            }
        } catch {
            // A new loading state or leaving the screen cancels presentation timing.
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch viewModel.state {
        case .idle:
            VikuStatusView(
                systemImage: "magnifyingglass",
                title: String(localized: "Search Tasks", bundle: .module),
                message: searchHint,
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

        case .loading:
            Color.clear.listRowSeparator(.hidden).listRowBackground(Color.clear)

        case let .loaded(tasks):
            if tasks.isEmpty {
                VikuStatusView(
                    systemImage: "magnifyingglass",
                    title: String(localized: "No Results", bundle: .module),
                    message: String(localized: "No tasks match your search", bundle: .module),
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                loadedContent(tasks)
            }

        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Search Error", bundle: .module),
                message: message,
                fillsHeight: false,
            )
            .padding(.top, VikuSpacing.lg)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private var searchHint: Text {
        var text = (try? AttributedString(
            markdown: viewModel.searchHint,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
        )) ?? AttributedString(viewModel.searchHint)
        for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].font = VikuFont.subheadline.monospaced()
            text[run.range].backgroundColor = palette.fieldBackground
        }
        return Text(text)
    }

    @ViewBuilder
    private func loadedContent(_ tasks: [VikunjaTask]) -> some View {
        HStack(spacing: VikuSpacing.xs) {
            Text("RESULTS", bundle: .module)
                .fontWeight(.bold)
            Text(verbatim: "\(tasks.count)")
                .fontWeight(.regular)
        }
        .vikuSectionHeader()
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
                        router.push(.taskDetail(task, project))
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
                        Button(String(localized: "Delete", bundle: .module), systemImage: "trash", role: .destructive) {
                            taskPendingDelete = task
                        }
                        .tint(palette.semanticDanger)
                    },
                )
                .vikuCardRow(index: index, count: tasks.count)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SearchView(viewModel: SearchViewModel(
            taskRepository: PreviewTaskRepository(),
            searchRepository: PreviewTaskRepository(),
            projectRepository: PreviewProjectRepository(),
            toastPresenter: PreviewToastPresenter(),
        ))
        .environment(AppRouter())
    }
}

private extension View {
    /// See `TodayView.todayListStyle()` for why `listRowSpacing(0)` and a
    /// zeroed `defaultMinListRowHeight` are needed alongside `.plain`, and
    /// why `listRowSpacing` is gated to iOS.
    @ViewBuilder
    func searchListStyle() -> some View {
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

// MARK: - Preview Helpers

private final class PreviewTaskRepository: @unchecked Sendable, TaskRepositoryProtocol, TaskSearchRepositoryProtocol {
    func searchTasks(matching _: TaskSearchQuery) async throws -> [VikunjaTask] {
        []
    }

    func fetchTasks(projectID _: EntityID) async throws -> [VikunjaTask] {
        []
    }

    func fetchTask(id _: EntityID) async throws -> VikunjaTask {
        VikunjaTask(id: 0, title: "", projectID: 0)
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func delete(id _: EntityID) async throws {}
    func searchTasks(query _: String) async throws -> [VikunjaTask] {
        []
    }
}

private final class PreviewProjectRepository: @unchecked Sendable, ProjectRepositoryProtocol {
    func fetchProjects() async throws -> [Project] {
        []
    }

    func fetchProject(id _: EntityID) async throws -> Project {
        Project(id: 0, title: "")
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id _: EntityID) async throws {}
}

private final class PreviewToastPresenter: @unchecked Sendable, ToastPresenting {
    func show(_: String, style _: VikunjaCore.ToastStyle) {}
}
