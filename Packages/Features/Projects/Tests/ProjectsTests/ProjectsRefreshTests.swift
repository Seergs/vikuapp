import Foundation
@testable import Projects
import Testing
import VikunjaCore

private actor ManualSync: SyncTriggering {
    private(set) var refreshCount = 0
    private let action: @Sendable () async throws -> Void

    private var initialized: Bool

    init(initialized: Bool = true, action: @escaping @Sendable () async throws -> Void) {
        self.initialized = initialized
        self.action = action
    }

    func hasInitialSnapshot() async throws -> Bool {
        initialized
    }

    func prepare() async throws {
        if !initialized {
            try await action()
            initialized = true
        }
    }

    func refresh(scope: SyncScope) async throws {
        refreshCount += 1
        try await action()
        initialized = true
    }
}

private actor ControlledChanges: LocalDataObserving {
    private let stream: AsyncThrowingStream<Void, Error>
    private let continuation: AsyncThrowingStream<Void, Error>.Continuation

    init() {
        (self.stream, self.continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        stream
    }

    func signal() {
        continuation.yield(())
    }
}

@MainActor
struct ProjectsRefreshTests {
    private func makeModel(
        repository: FakeProjectRepository,
        sync: ManualSync,
        toast: FakeToastPresenter,
    ) -> ProjectsListViewModel {
        ProjectsListViewModel(
            syncTrigger: sync, localData: TestScreenSync(), repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(), taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: toast,
        )
    }

    @Test
    func `load is local while refresh runs sync and re-reads the cache`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: -3, title: "Old filter")]
        let sync = ManualSync { repository.projects = [Project(id: -3, title: "Renamed filter")] }
        let model = makeModel(repository: repository, sync: sync, toast: FakeToastPresenter())
        await model.load()
        #expect(await sync.refreshCount == 0)
        #expect(model.pseudoNodes.map(\.project.title) == ["Old filter"])
        await model.refresh()
        #expect(await sync.refreshCount == 1)
        #expect(model.pseudoNodes.map(\.project.title) == ["Renamed filter"])
        #expect(model.loadState == .loaded)
    }

    @Test
    func `offline refresh preserves cached content and shows an informational notice`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Cached")]
        let sync = ManualSync { throw VikunjaError.offline }
        let toast = FakeToastPresenter()
        let model = makeModel(repository: repository, sync: sync, toast: toast)
        await model.load()
        await model.refresh()
        #expect(model.rootNodes.map(\.project.title) == ["Cached"])
        #expect(model.loadState == .loaded)
        #expect(toast.shownMessages.last?.style == .info)
        #expect(toast.shownMessages.last?.message == VikunjaError.offline.displayMessage)
    }

    @Test
    func `failed refresh preserves the visible tree and reports an error`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Cached")]
        let sync = ManualSync { throw VikunjaError.network("offline") }
        let toast = FakeToastPresenter()
        let model = makeModel(repository: repository, sync: sync, toast: toast)
        await model.load()
        await model.refresh()
        #expect(model.rootNodes.map(\.project.title) == ["Cached"])
        #expect(model.loadState == .loaded)
        #expect(toast.shownMessages.last?.style == .error)
    }

    @Test
    func `refresh shows successfully downloaded data even when another sync phase fails`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Before")]
        let sync = ManualSync {
            repository.projects = [Project(id: 1, title: "Downloaded")]
            throw VikunjaError.network("upload failed")
        }
        let toast = FakeToastPresenter()
        let model = makeModel(repository: repository, sync: sync, toast: toast)
        await model.load()
        await model.refresh()
        #expect(model.rootNodes.map(\.project.title) == ["Downloaded"])
        #expect(model.loadState == .loaded)
        #expect(toast.shownMessages.last?.style == .error)
    }

    @Test
    func `a new account explicitly downloads its initial snapshot`() async {
        let repository = FakeProjectRepository()
        let sync = ManualSync(initialized: false) {
            repository.projects = [Project(id: 1, title: "First download")]
        }
        let model = makeModel(repository: repository, sync: sync, toast: FakeToastPresenter())
        await model.start()
        #expect(model.rootNodes.map(\.project.title) == ["First download"])
        #expect(model.displayLoadState == .loaded)
    }

    @Test
    func `an initial sync error cannot turn into a misleading empty account on a local reload`() async {
        let repository = FakeProjectRepository()
        let sync = ManualSync(initialized: false) { throw VikunjaError.network("offline") }
        let model = makeModel(repository: repository, sync: sync, toast: FakeToastPresenter())
        await model.start()
        await model.load()
        #expect(model.rootNodes.isEmpty)
        #expect(model.displayLoadState == .failure(VikunjaError.network("offline").displayMessage))
    }

    @Test
    func `refresh recovers from a failed initial download`() async {
        let repository = FakeProjectRepository()
        repository.fetchError = .network("offline")
        let sync = ManualSync(initialized: false) {
            if let error = repository.fetchError {
                throw error
            }
            repository.projects = [Project(id: 1, title: "Recovered")]
        }
        let model = makeModel(repository: repository, sync: sync, toast: FakeToastPresenter())
        await model.start()
        repository.fetchError = nil
        await model.refresh()
        #expect(model.displayLoadState == .loaded)
        #expect(model.rootNodes.map(\.project.title) == ["Recovered"])
    }

    @Test
    func `a visible screen follows local changes without requesting another sync`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Before")]
        let sync = ManualSync {}
        let changes = ControlledChanges()
        let model = ProjectsListViewModel(
            syncTrigger: sync, localData: changes, repository: repository, taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(), taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )
        await model.load()
        let observation = Task { await model.observeLocalChanges() }
        defer { observation.cancel() }
        repository.projects = [Project(id: 1, title: "Arrived from background sync")]
        await changes.signal()
        let deadline = Date().addingTimeInterval(2)
        while model.rootNodes.first?.project.title != "Arrived from background sync", Date() < deadline {
            await Task.yield()
        }
        #expect(model.rootNodes.map(\.project.title) == ["Arrived from background sync"])
        #expect(await sync.refreshCount == 0)
        observation.cancel()
        await observation.value
    }

    @Test
    func `a mutation response does not update a stale row index after a local reload`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Project")]
        let taskRepository = FakeTaskRepository()
        let task = VikunjaTask(id: 1, title: "Task", projectID: 1)
        taskRepository.tasks = [task]
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(), project: repository.projects[0],
            repository: taskRepository, projectRepository: repository, labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(), filterRepository: FakeFilterRepository(),
            capabilityProvider: FakeCapabilityProvider(), toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await model.load()
        taskRepository.beforeUpdate = {
            taskRepository.tasks = []
            await model.load()
        }
        await model.toggleDone(task)
        #expect(model.tasks.isEmpty)
        taskRepository.beforeUpdate = nil
    }
}
