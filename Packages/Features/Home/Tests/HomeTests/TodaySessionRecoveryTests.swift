import Foundation
@testable import Home
import Testing
import VikunjaCore

@MainActor
struct TodaySessionRecoveryTests {
    @Test(arguments: [false, true])
    func `recovery keeps cached tasks and downloads without manual refresh`(hasCachedTask: Bool) async {
        let tasks = FakeTaskRepository()
        tasks.tasks = hasCachedTask ? [VikunjaTask(id: 1, title: "Cached", projectID: 1)] : []
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work")]
        let sync = RecoveryScreenSync {
            tasks.tasks = [VikunjaTask(id: 2, title: "Fresh", projectID: 1)]
        }
        let viewModel = makeViewModel(tasks: tasks, projects: projects, sync: sync)
        let request = Task { await viewModel.start() }
        for await _ in sync.started.stream {}
        #expect(viewModel.tasks.map(\.title) == (hasCachedTask ? ["Cached"] : []))
        #expect(viewModel.isLoading == !hasCachedTask)
        sync.release.continuation.finish()
        await request.value
        #expect(viewModel.tasks.map(\.title) == ["Fresh"])
        #expect(viewModel.displayLoadState.isLoaded)
    }

    @Test(arguments: [false, true])
    func `recovery failure keeps saved data and offers retry`(hasCachedTask: Bool) async {
        let tasks = FakeTaskRepository()
        tasks.tasks = hasCachedTask ? [VikunjaTask(id: 1, title: "Cached", projectID: 1)] : []
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work")]
        let toast = FakeToastPresenter()
        let sync = RecoveryScreenSync {}
        sync.error = .offline
        sync.release.continuation.finish()
        let viewModel = makeViewModel(tasks: tasks, projects: projects, sync: sync, toast: toast)
        await viewModel.start()
        #expect(viewModel.tasks.map(\.title) == (hasCachedTask ? ["Cached"] : []))
        if hasCachedTask {
            #expect(viewModel.displayLoadState.isLoaded)
            #expect(toast.shownMessages.count == 1)
        } else {
            #expect(viewModel.displayLoadState.failureMessage == VikunjaError.offline.displayMessage)
        }
        sync.error = nil
        await viewModel.refresh()
        #expect(viewModel.displayLoadState.isLoaded)
        #expect(!viewModel.isLoading)
    }

    @Test func `leaving during recovery does not show an error`() async {
        let tasks = FakeTaskRepository()
        let projects = FakeProjectRepository()
        let toast = FakeToastPresenter()
        let sync = RecoveryScreenSync {}
        let viewModel = makeViewModel(tasks: tasks, projects: projects, sync: sync, toast: toast)
        let request = Task { await viewModel.start() }
        for await _ in sync.started.stream {}
        request.cancel()
        sync.release.continuation.finish()
        await request.value
        #expect(toast.shownMessages.isEmpty)
        #expect(viewModel.displayLoadState.failureMessage == nil)
    }

    private func makeViewModel(
        tasks: FakeTaskRepository, projects: FakeProjectRepository, sync: RecoveryScreenSync,
        toast: FakeToastPresenter = FakeToastPresenter(),
    ) -> TodayViewModel {
        TodayViewModel(
            syncTrigger: sync, localData: sync, taskRepository: tasks, bulkUpdateRepository: tasks,
            projectRepository: projects, labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(), toastPresenter: toast,
        )
    }
}

@MainActor
private final class RecoveryScreenSync: SyncTriggering, LocalDataObserving {
    let started = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    var error: VikunjaError?
    private var pending = true
    private let download: () -> Void

    init(download: @escaping () -> Void) {
        self.download = download
    }

    func hasInitialSnapshot() async throws -> Bool {
        !pending
    }

    func prepare() async throws {
        try await refresh(scope: .account)
    }

    func refresh(scope _: SyncScope) async throws {
        started.continuation.finish()
        for await _ in release.stream {}
        try Task.checkCancellation()
        if let error {
            throw error
        }
        download()
        pending = false
    }

    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
