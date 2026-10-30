import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// A single project's Kanban board: one horizontally scrolling column per
/// bucket, each holding that bucket's tasks as draggable cards.
///
/// Takes a plain closure for the one cross-feature push it needs
/// (`onSelectTask`), mirroring `ProjectOverviewView` — Kanban itself never
/// imports `VikuNavigation`'s `AppRoute` or touches `AppRouter` directly, so
/// the caller decides how opening a task's detail is routed.
///
/// No `navigationTitle`/toolbar of its own: this is meant to swap in as the
/// body of a screen that already has both (the List/Kanban toggle on a
/// project's overview), not to be a destination in its own right.
public struct KanbanBoardView: View {
    @Bindable var viewModel: KanbanBoardViewModel
    /// Mirrors `ProjectOverviewView`'s own `filteredTasks`: narrows each
    /// bucket's cards to the in-flight search text, by title only, without
    /// touching `viewModel.buckets` itself so drag-to-move and the
    /// done-bucket lookups in `KanbanBoardViewModel` keep seeing every task.
    let searchText: String
    let onSelectTask: (VikunjaTask) -> Void

    @State private var horizontalScrollPosition: Int?
    @Environment(\.vikuPalette) private var palette

    public init(
        viewModel: KanbanBoardViewModel,
        searchText: String = "",
        onSelectTask: @escaping (VikunjaTask) -> Void,
    ) {
        self.viewModel = viewModel
        self.searchText = searchText
        self.onSelectTask = onSelectTask
    }

    private var filteredBuckets: [KanbanBucket] {
        guard !searchText.isEmpty else { return viewModel.buckets }
        return viewModel.buckets.map { bucket in
            var filtered = bucket
            filtered.tasks = bucket.tasks.filter { $0.title.localizedStandardContains(searchText) }
            return filtered
        }
    }

    public var body: some View {
        // Keep a vertical scroll surface for navigation styling. Each column's
        // List owns its native pull-to-refresh and card scrolling.
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .refreshable { await viewModel.refresh() }
        }
        .background(palette.pageBackground)
        .task { await viewModel.start() }
        .task { await viewModel.observeLocalChanges() }
    }

    private var content: some View {
        VStack(spacing: VikuSpacing.sm) {
            HStack {
                Spacer()
                if viewModel.isRefreshing, viewModel.hasSnapshot {
                    ProgressView()
                }
                Button { Task { await viewModel.refresh() } } label: {
                    Label { Text("Refresh", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
                }
                .disabled(viewModel.isRefreshing || viewModel.needsProjectSync)
            }
            .padding(.horizontal, VikuSpacing.md)
            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failure(message):
                VikuStatusView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: String(localized: "Couldn't load this board", bundle: .module),
                    message: message,
                    retry: { Task { await viewModel.refresh() } },
                )
            case .loaded:
                if !viewModel.hasSnapshot {
                    VikuStatusView(
                        systemImage: "icloud.and.arrow.down",
                        title: String(localized: "Board unavailable", bundle: .module),
                        message: unavailableMessage,
                    )
                } else if viewModel.buckets.isEmpty {
                    VikuStatusView(
                        systemImage: "rectangle.split.3x1",
                        title: String(localized: "This board is empty", bundle: .module),
                        message: String(localized: "Refresh to check for columns.", bundle: .module),
                    )
                } else {
                    if !viewModel.supportsWrites {
                        Text("This board uses server rules. Use Vikunja's web app to make changes.", bundle: .module)
                            .font(VikuFont.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, VikuSpacing.md)
                    }
                    board
                }
            }
        }
    }

    private var unavailableMessage: String {
        if viewModel.needsProjectSync {
            String(localized: "Sync this project before downloading its board.", bundle: .module)
        } else {
            String(localized: "Connect and refresh to download this board for offline use.", bundle: .module)
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: VikuSpacing.md) {
                ForEach(filteredBuckets) { bucket in
                    KanbanColumnView(
                        bucket: bucket,
                        allowsMutations: viewModel.supportsWrites,
                        allowsTaskCreation: viewModel.supportsTaskCreation,
                        onRefresh: { await viewModel.refresh() },
                        onSelectTask: onSelectTask,
                        onToggleDone: { task in Task { await viewModel.toggleDone(task) } },
                        onDropTaskID: { taskID in
                            Task { await viewModel.moveTask(taskID: taskID, to: bucket) }
                        },
                        onAddTask: { title in Task { await viewModel.createTask(title: title, in: bucket) } },
                    )
                }
            }
            .padding(VikuSpacing.md)
            .scrollTargetLayout()
        }
        // Keep the visible bucket anchored while SwiftUI temporarily updates
        // a List's drag presentation. Without an identity anchor, the nested
        // horizontal scroll can jump back to its leading edge on drag start.
        .scrollPosition(id: $horizontalScrollPosition)
        .scrollIndicators(.hidden)
    }
}

#Preview {
    KanbanBoardView(
        viewModel: KanbanBoardViewModel(
            project: Project(id: 1, title: "Work"),
            repository: PreviewBucketRepository(),
            syncTrigger: PreviewScreenSync(), localData: PreviewScreenSync(),
            toastPresenter: PreviewToastPresenter(),
        ),
        onSelectTask: { _ in },
    )
}

// MARK: - Preview Helpers

private actor PreviewBucketRepository: KanbanBoardRepositoryProtocol {
    func hasCachedKanbanSupport() async throws -> Bool {
        true
    }

    func fetchBoard(projectID: EntityID, viewID: Int?) async throws -> KanbanBoardSnapshot {
        .available(KanbanBoard(viewID: 1, buckets: [
            KanbanBucket(
                id: 1, title: "To Do", tasks: [VikunjaTask(id: 1, title: "Write proposal", projectID: projectID)],
            ),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ], defaultBucketID: 1, supportsWrites: true, lastPulledAt: Date()))
    }

    func createTask(title: String, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask {
        VikunjaTask(id: .local(UUID()), title: title, projectID: projectID)
    }

    func moveTask(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask {
        VikunjaTask(id: taskID, title: "Write proposal", isDone: bucketID == 2, projectID: projectID)
    }
}

private struct PreviewScreenSync: SyncTriggering, LocalDataObserving {
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {}
    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct PreviewToastPresenter: ToastPresenting {
    func show(_: String, style _: ToastStyle) {}
}
