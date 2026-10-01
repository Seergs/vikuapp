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
    let onSelectTask: (VikunjaTask) -> Void

    public init(viewModel: KanbanBoardViewModel, onSelectTask: @escaping (VikunjaTask) -> Void) {
        self.viewModel = viewModel
        self.onSelectTask = onSelectTask
    }

    public var body: some View {
        content
            .background(VikuColor.Surface.page)
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
                ForEach(viewModel.buckets) { bucket in
                    KanbanColumnView(
                        bucket: bucket,
                        onSelectTask: onSelectTask,
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
