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
        // iOS 26 decides the navigation bar's at-rest background through the
        // "scroll edge effect": it reads the vertical scroll position of
        // whatever's directly underneath it, and only recognizes a single
        // vertical `List`/`ScrollView` as that signal. This board has no
        // such thing — it scrolls horizontally, and each column scrolls
        // vertically on its own — so without one, the bar falls back to the
        // system's own default material instead of matching
        // `palette.pageBackground`, a mismatch visible only on real-device
        // compositing. Forcing the bar's own `.toolbarBackground` to match
        // was tried from the caller's side first; it works, but combined
        // with a large `.navigationTitle` it hits a documented iOS 26 bug
        // (e.g. FB19434429/FB24528594) where the title stops rendering
        // entirely, not just intermittently.
        //
        // Giving the heuristic the vertical scroll view it's looking for,
        // instead of fighting it from outside, sidesteps that bug: a
        // `ScrollView` sized to exactly fill the available height always
        // reports a content offset of zero (nothing to scroll past), the
        // same "at rest, at the top" state a `List` that fits on one screen
        // reports — `.scrollDisabled(true)` keeps it from intercepting any
        // gestures, so panning between columns and each column's own
        // vertical scrolling are unaffected.
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .scrollDisabled(true)
        }
        .background(palette.pageBackground)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Couldn't load this board",
                message: message,
                retry: { Task { await viewModel.load() } },
            )
        case .loaded:
            board
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: VikuSpacing.md) {
                ForEach(filteredBuckets) { bucket in
                    KanbanColumnView(
                        bucket: bucket,
                        onSelectTask: onSelectTask,
                        onToggleDone: { task in Task { await viewModel.toggleDone(task) } },
                        onDropTaskID: { taskID in
                            guard let task = viewModel.buckets.flatMap(\.tasks).first(where: { $0.id == taskID })
                            else { return }
                            Task { await viewModel.moveTask(task, to: bucket) }
                        },
                        onAddTask: { title in Task { await viewModel.createTask(title: title, in: bucket) } },
                    )
                }
            }
            .padding(VikuSpacing.md)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    KanbanBoardView(
        viewModel: KanbanBoardViewModel(
            project: Project(id: 1, title: "Work"),
            repository: PreviewBucketRepository(),
            toastPresenter: PreviewToastPresenter(),
        ),
        onSelectTask: { _ in },
    )
}

// MARK: - Preview Helpers

private final class PreviewBucketRepository: @unchecked Sendable, BucketRepositoryProtocol {
    func fetchBuckets(projectID _: Int) async throws -> [KanbanBucket] {
        [
            KanbanBucket(
                id: 1,
                title: "To Do",
                tasks: [
                    VikunjaTask(id: 1, title: "Write proposal", priority: .high, projectID: 1),
                    VikunjaTask(id: 2, title: "Plan sprint", projectID: 1),
                ],
            ),
            KanbanBucket(
                id: 2,
                title: "Doing",
                tasks: [VikunjaTask(id: 3, title: "Fix onboarding bug", priority: .urgent, projectID: 1)],
            ),
            KanbanBucket(
                id: 3,
                title: "Done",
                isDoneBucket: true,
                tasks: [VikunjaTask(id: 4, title: "Ship release", isDone: true, projectID: 1)],
            ),
        ]
    }

    func moveTask(taskID: Int, toBucketID _: Int, projectID: Int) async throws -> VikunjaTask {
        VikunjaTask(id: taskID, title: "", projectID: projectID)
    }

    func createTask(_ task: VikunjaTask, bucketID _: Int, projectID: Int) async throws -> VikunjaTask {
        VikunjaTask(id: Int.random(in: 1000 ... 9999), title: task.title, projectID: projectID)
    }
}

private final class PreviewToastPresenter: @unchecked Sendable, ToastPresenting {
    func show(_: String, style _: ToastStyle) {}
}
