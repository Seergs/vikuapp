import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives a single project's overview screen: loads that project's tasks
/// from the server. A different project gets a new view model rather than
/// this one being repointed, but `project` itself is still refreshed by
/// `load()` (see its doc comment) — this screen's view model is cached
/// indefinitely per project id, so editing the project's own name or color
/// needs a live re-fetch to show up on a revisit, not just a new instance.
@MainActor
@Observable
public final class ProjectOverviewViewModel {
    public private(set) var project: Project
    /// This project's direct children. Seeded at construction from the
    /// already-built tree (`ProjectsListViewModel.tree(from:)`) so the first
    /// render has something to show immediately, then replaced by a fresh
    /// fetch every time `load()` runs. This screen's view model is cached
    /// indefinitely per project id (see `ProjectsRootView`), so a
    /// construction-time snapshot that `load()` never refreshed would go
    /// stale the moment a subproject is created, deleted, or moved from
    /// anywhere else in the app — `load()` re-fetching it is what keeps a
    /// revisit to this screen correct, not just fast.
    public private(set) var subprojects: [ProjectNode]
    public private(set) var tasks: [VikunjaTask] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Reachability state drives the saved-filter snapshot notice. Regular
    /// projects and Favorites don't need to expose the filter-query caveat.
    public private(set) var isOffline = false
    /// Runtime API-v2 support or an already downloaded board enables Kanban
    /// for projects and saved filters. Favorites have no Kanban view.
    public private(set) var supportsKanban = false
    /// This saved filter's raw query (e.g. `priority >= 3 && done = false`),
    /// shown read-only under its badge. `nil` for a real project or
    /// Favorites, and also `nil` if the fetch fails or the filter has no
    /// query set - either way the query line just doesn't render, no error
    /// banner for what's a nice-to-have display. See `SavedFilterDetail`.
    public private(set) var savedFilterQuery: String?
    /// Each subproject's own task completion count, keyed by project id, for
    /// the "Subprojects" cards. Fetched alongside this project's own tasks
    /// since `ProjectNode` only carries project metadata, not tasks.
    public private(set) var subprojectTaskSummaries: [EntityID: TaskSummary] = [:]
    /// Every project on the instance, for the "Move to Project" picker —
    /// loaded lazily via `loadMoveCandidates()` rather than alongside
    /// `load()`, since most visits to this screen never open that picker.
    public private(set) var allProjects: [Project] = []
    /// Every label on the instance, for the label picker sheet - loaded
    /// lazily via `loadAllLabels()`, mirroring `allProjects`.
    public private(set) var allLabels: [Label] = []
    /// Candidates for the "add relation" task picker, from the most recent
    /// `searchTasksForRelation(for:query:)` call.
    public private(set) var relationSearchResults: [VikunjaTask] = []

    public var isLoading: Bool {
        loadState == .loading
    }

    /// `subprojects` narrowed to the ones worth surfacing on this screen: a
    /// child with no tasks pending (brand new with none yet, or fully
    /// completed) has nothing actionable here, so it's left out rather than
    /// cluttering the "Subprojects" row with a dead end. A child whose
    /// summary hasn't loaded yet (not present in `subprojectTaskSummaries`)
    /// is kept rather than hidden, so it doesn't flash away the instant
    /// `load()` starts and then reappear once the fetch resolves.
    public var subprojectsWithPendingTasks: [ProjectNode] {
        subprojects.filter { node in
            guard let summary = subprojectTaskSummaries[node.id] else { return true }
            return summary.done < summary.total
        }
    }

    public var sortField: TaskSort.Field {
        get { taskSortStore.taskSort.field }
        set { taskSortStore.setTaskSort(TaskSort(field: newValue, direction: sortDirection)) }
    }

    public var sortDirection: TaskSort.Direction {
        get { taskSortStore.taskSort.direction }
        set { taskSortStore.setTaskSort(TaskSort(field: sortField, direction: newValue)) }
    }

    private let repository: TaskRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    /// Only consulted when `project.kind == .savedFilter` — its local-first
    /// implementation queues filter mutations against the positive `/filters`
    /// id, while `projectRepository` sees the negative pseudo-project id.
    private let filterRepository: FilterRepositoryProtocol
    private let capabilityProvider: CapabilityProvider
    private let kanbanRepository: KanbanBoardRepositoryProtocol?
    private let mutator: TaskListMutator
    private let taskSortStore: TaskSortStore
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting
    /// Set by `AppContainer` so this screen can tell the globally-presented
    /// quick-add sheet which project to default to while it's on screen.
    /// Optional so tests and any caller that doesn't care can skip it.
    private let quickAddContext: QuickAddContextTracking?
    /// Set by `AppContainer` so this screen learns when the quick-add sheet
    /// creates a task for it, to refresh live. Optional so tests and any
    /// caller that doesn't care can skip it.
    private let taskChangeBroadcaster: TaskChangeBroadcasting?
    private let reachabilityUpdates: @Sendable () async -> AsyncStream<Bool>

    private let synchronization: LocalScreenSync
    private var loadVersion = 0

    public init(
        syncTrigger: SyncTriggering,
        localData: LocalDataObserving,
        project: Project,
        subprojects: [ProjectNode] = [],
        repository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        filterRepository: FilterRepositoryProtocol,
        capabilityProvider: CapabilityProvider = NoopCapabilityProvider(),
        kanbanRepository: KanbanBoardRepositoryProtocol? = nil,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
        taskSortStore: TaskSortStore,
        quickAddContext: QuickAddContextTracking? = nil,
        taskChangeBroadcaster: TaskChangeBroadcasting? = nil,
        reachabilityUpdates: @escaping @Sendable () async -> AsyncStream<Bool> = {
            AsyncStream { continuation in
                continuation.yield(true)
                continuation.finish()
            }
        },
    ) {
        self.synchronization = LocalScreenSync(
            trigger: syncTrigger, localData: localData, toastPresenter: toastPresenter,
        )
        self.project = project
        self.subprojects = subprojects
        self.repository = repository
        self.projectRepository = projectRepository
        self.labelRepository = labelRepository
        self.relationRepository = relationRepository
        self.filterRepository = filterRepository
        self.capabilityProvider = capabilityProvider
        self.kanbanRepository = kanbanRepository
        self.taskSortStore = taskSortStore
        self.mutator = TaskListMutator(
            repository: repository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
            errorMessage: { ($0 as? VikunjaError)?.displayMessage ?? $0.localizedDescription },
        )
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
        self.quickAddContext = quickAddContext
        self.taskChangeBroadcaster = taskChangeBroadcaster
        self.reachabilityUpdates = reachabilityUpdates
    }

    /// Mirrors `taskChangeBroadcaster`'s most recent event, filtered to this
    /// project. The view observes this via `.onChange(of:)` and reloads when
    /// it changes, so a task created here through the quick-add sheet shows
    /// up immediately instead of waiting for the next pull-to-refresh.
    public var lastCreatedTaskForThisProject: TaskCreatedEvent? {
        guard let event = taskChangeBroadcaster?.lastCreatedTask, event.projectID == project.id else {
            return nil
        }
        return event
    }

    /// Call from the view's `onAppear`/`onDisappear`: while this project's
    /// overview is the visible screen, a quick-add from the tab-bar FAB
    /// defaults to this project instead of the account default. Favorites
    /// and saved filters are pseudo-projects with negative ids that can't
    /// hold a task, so they're skipped here and quick-add falls through to
    /// the account default instead.
    public func markVisible() {
        guard project.kind == .project else { return }
        quickAddContext?.enterProjectScope(project)
    }

    public func markHidden() {
        guard project.kind == .project else { return }
        quickAddContext?.exitProjectScope(project)
    }

    /// Keeps the offline notice in step with connectivity while this screen
    /// is visible. The view owns the task so SwiftUI cancels the stream when
    /// the screen disappears.
    public func observeReachability() async {
        for await isReachable in await reachabilityUpdates() {
            isOffline = !isReachable
        }
    }

    /// Kept as a nested name for call sites that already spell it
    /// `ProjectOverviewViewModel.TaskSummary`; the type itself is shared with
    /// the projects list (see `ProjectTaskSummary`).
    public typealias TaskSummary = ProjectTaskSummary

    /// Skips the `.loading` transition when there's already loaded content
    /// (i.e. this is a pull-to-refresh): swapping the list out for a
    /// spinner mid-refresh would tear down the `List` that owns the
    /// in-flight `.refreshable` task, cancelling its request underneath it.
    ///
    /// Re-fetches `project` and `subprojects` from the server every time
    /// rather than trusting the construction-time snapshot — this screen's
    /// view model is cached indefinitely (see `ProjectsRootView`), so without
    /// this neither a rename/recolor of this project nor a subproject
    /// created, deleted, or moved anywhere else in the app (e.g. the root
    /// Projects list) would ever show up here on a revisit, only after the
    /// app relaunches. A failed project re-fetch fails the whole load, same
    /// as a failed `tasks`/`subprojects` fetch already does.
    public func load() async {
        loadVersion += 1
        let version = loadVersion
        let hadContent = loadState == .loaded
        if !hadContent {
            loadState = .loading
        }
        async let kanbanSupport = resolveKanbanSupport()
        do {
            let fetchedProject = try await projectRepository.fetchProject(id: project.id)
            let fetchedTasks = try await repository.fetchTasks(projectID: fetchedProject.id)
            let fetchedSubprojects = try await Self.fetchSubprojects(
                parentID: fetchedProject.id, repository: projectRepository,
            )
            let summaries = await Self.fetchSubprojectSummaries(fetchedSubprojects, repository: repository)
            var query: String?
            if let filterID = fetchedProject.savedFilterID {
                query = try? await filterRepository.fetchFilter(id: filterID).query
            }
            guard version == loadVersion else { return }
            project = fetchedProject
            tasks = fetchedTasks
            subprojects = fetchedSubprojects
            subprojectTaskSummaries = summaries
            savedFilterQuery = query?.isEmpty == false ? query : nil
            loadState = .loaded
        } catch let error as VikunjaError {
            guard version == loadVersion else { return }
            if hadContent {
                toastPresenter.show(error.displayMessage, style: .error)
            } else {
                loadState = .failure(error.displayMessage)
            }
        } catch {
            guard version == loadVersion else { return }
            if hadContent {
                toastPresenter.show(error.localizedDescription, style: .error)
            } else {
                loadState = .failure(error.localizedDescription)
            }
        }
        let serverSupportsKanban = await kanbanSupport
        guard version == loadVersion else { return }
        supportsKanban = project.kind != .favorites && serverSupportsKanban
    }

    private func resolveKanbanSupport() async -> Bool {
        guard project.kind != .favorites else { return false }
        if let kanbanRepository, await (try? kanbanRepository.hasCachedKanbanSupport()) == true {
            return true
        }
        return await capabilityProvider.supports(.apiV2)
    }

    /// This project's current direct children, straight from the server —
    /// mirrors `ProjectsListViewModel.tree(from:)`'s own filtering (drop
    /// archived, order by position) but only one level deep, since this
    /// screen only ever shows direct children as "Subprojects" cards.
    private static func fetchSubprojects(
        parentID: EntityID,
        repository: ProjectRepositoryProtocol,
    ) async throws -> [ProjectNode] {
        try await repository.fetchProjects()
            .filter { !$0.isArchived && $0.parentProjectID == parentID }
            .sorted { $0.position < $1.position }
            .map { ProjectNode(project: $0) }
    }

    /// Fetches each subproject's own tasks concurrently so the "Subprojects"
    /// cards can show a real completion count instead of just a child-project
    /// count. A subproject whose fetch fails is left out rather than failing
    /// the whole screen — its card just falls back to "No tasks yet".
    private static func fetchSubprojectSummaries(
        _ nodes: [ProjectNode],
        repository: TaskRepositoryProtocol,
    ) async -> [EntityID: TaskSummary] {
        await withTaskGroup(of: (EntityID, TaskSummary)?.self) { group in
            for node in nodes {
                group.addTask {
                    guard let tasks = try? await repository.fetchTasks(projectID: node.id) else { return nil }
                    return (node.id, TaskSummary(done: tasks.filter(\.isDone).count, total: tasks.count))
                }
            }
            var summaries: [EntityID: TaskSummary] = [:]
            for await result in group {
                if let (id, summary) = result {
                    summaries[id] = summary
                }
            }
            return summaries
        }
    }

    /// Flips a task's completion state, persists the change, and rolls the
    /// local flip back if the server rejects it — so a failed request never
    /// leaves the row showing a state the server doesn't actually have.
    public func toggleDone(_ task: VikunjaTask) async {
        loadVersion += 1
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var flipped = task
        flipped.isDone.toggle()
        tasks[index] = flipped
        let result = await mutator.persistToggleDone(flipped: flipped, original: task)
        acceptMutationResult(result, replacing: flipped)
    }

    /// Sets a task's priority, persists the change, and rolls the local edit
    /// back if the server rejects it - mirrors `toggleDone(_:)`.
    public func setPriority(_ task: VikunjaTask, to priority: VikunjaTask.Priority) async {
        loadVersion += 1
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.priority = priority
        tasks[index] = updated
        let result = await mutator.persistSetPriority(updated: updated, original: task)
        acceptMutationResult(result, replacing: updated)
    }

    /// Sets (or clears, via `nil`) a task's due date, persists the change,
    /// and rolls the local edit back if the server rejects it - mirrors
    /// `setPriority(_:to:)`.
    public func setDueDate(_ task: VikunjaTask, to dueDate: Date?) async {
        loadVersion += 1
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.dueDate = dueDate
        tasks[index] = updated
        let result = await mutator.persistSetDueDate(updated: updated, original: task)
        acceptMutationResult(result, replacing: updated)
    }

    /// Adds or removes `label` from `task`, persists the change, and rolls
    /// the local edit back if the server rejects it - mirrors
    /// `setPriority(_:to:)`. Task labels are read-only through the plain
    /// task update endpoint, so this routes through the label repository
    /// rather than `mutator.persistSetPriority`'s `repository.update(_:)`.
    public func toggleLabel(_ task: VikunjaTask, _ label: Label) async {
        loadVersion += 1
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let original = tasks[index]
        var updated = original
        let isAdding = !updated.labels.contains(label)
        if isAdding {
            updated.labels.append(label)
        } else {
            updated.labels.removeAll { $0.id == label.id }
        }
        tasks[index] = updated
        let result = await mutator.persistToggleLabel(
            updated: updated, original: original, label: label, isAdding: isAdding, labelRepository: labelRepository,
        )
        acceptMutationResult(result, replacing: updated)
    }

    /// Loads every label on the instance, for the label picker sheet.
    /// Failures leave `allLabels` at whatever it already was, mirroring
    /// `loadMoveCandidates()`.
    public func loadAllLabels() async {
        allLabels = await (try? labelRepository.fetchLabels()) ?? allLabels
    }

    /// Creates a new label on the instance and attaches it to `task` -
    /// mirrors `TaskDetailViewModel.createAndAddLabel(title:hexColor:)`.
    public func createAndAddLabel(_ task: VikunjaTask, title: String, hexColor: String) async {
        guard let created = try? await labelRepository.create(Label(id: 0, title: title, hexColor: hexColor)) else {
            return
        }
        allLabels.append(created)
        await toggleLabel(task, created)
    }

    /// Searches every task the account can see for the "add relation" task
    /// picker, excluding `task` itself and anything it's already related to
    /// - mirrors `TaskDetailViewModel.searchTasksForRelation(query:)`. An
    /// empty or all-whitespace query falls back to
    /// `loadRelationSuggestions(for:)` rather than clearing the results, so
    /// the picker never shows a blank list just because the user cleared
    /// their search. Failures leave `relationSearchResults` empty rather
    /// than surfacing an error - the sheet just shows no candidates.
    public func searchTasksForRelation(for task: VikunjaTask, query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await loadRelationSuggestions(for: task)
            return
        }
        let excludedIDs = relatedTaskIDs(of: task)
        let results = await (try? repository.searchTasks(query: query)) ?? []
        relationSearchResults = results.filter { !excludedIDs.contains($0.id) }
    }

    /// Populates `relationSearchResults` with `task`'s own project's other
    /// tasks before the user has typed anything - mirrors
    /// `TaskDetailViewModel.loadRelationSuggestions()`.
    public func loadRelationSuggestions(for task: VikunjaTask) async {
        let excludedIDs = relatedTaskIDs(of: task)
        let results = await (try? repository.fetchTasks(projectID: task.projectID)) ?? []
        relationSearchResults = results.filter { !excludedIDs.contains($0.id) }
    }

    /// `task`'s own id plus every relation it already carries, excluded from
    /// the "add relation" search so the same task can't be picked twice.
    /// Best-effort rather than exhaustive: unlike `TaskDetailViewModel`, this
    /// screen's tasks come from a list fetch, which doesn't always carry a
    /// task's relations.
    private func relatedTaskIDs(of task: VikunjaTask) -> Set<EntityID> {
        var ids = Set(task.dependsOn.map(\.id) + task.blocks.map(\.id))
        for relations in task.otherRelations.values {
            ids.formUnion(relations.map(\.id))
        }
        ids.insert(task.id)
        return ids
    }

    /// Adds `relation` under `kind` to `task`, optimistically updating the
    /// row (so its link glyph appears immediately) and rolling back if the
    /// server rejects it - mirrors `TaskDetailViewModel.addRelation(_:kind:)`.
    public func addRelation(_ relation: TaskRelation, kind: RelationKind, to task: VikunjaTask) async {
        loadVersion += 1
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let original = tasks[index]
        var updated = original
        updated.addRelation(relation, kind: kind)
        tasks[index] = updated
        let result = await mutator.persistAddRelation(
            relation, kind: kind, updated: updated, original: original, relationRepository: relationRepository,
        )
        acceptMutationResult(result, replacing: updated)
    }

    /// Deletes a task from the server and drops it from the local list on
    /// success. Vikunja soft-deletes tasks server-side rather than cascading
    /// the delete to subtasks/relations, so nothing else in the tree needs
    /// updating here.
    public func delete(_ task: VikunjaTask) async {
        loadVersion += 1
        if await mutator.delete(task) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    /// Loads every project on the instance, for the "Move to Project"
    /// picker. Failures leave `allProjects` at whatever it already was — the
    /// picker just shows fewer candidates, mirroring
    /// `TaskDetailViewModel.loadAllProjects()`.
    public func loadMoveCandidates() async {
        allProjects = await (try? projectRepository.fetchProjects())?.realProjectsOnly() ?? allProjects
    }

    /// Moves `task` to `destination` and drops it from the local list on
    /// success — it no longer belongs to this project's screen, mirroring
    /// `delete(_:)`.
    public func move(_ task: VikunjaTask, to destination: Project) async {
        loadVersion += 1
        if await mutator.move(task, to: destination) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    /// Appends a subproject just created from this screen's own "Add
    /// Subproject" button to the local tree and seeds its summary at 0/0,
    /// for instant feedback before the sheet even dismisses — `load()` would
    /// also pick it up correctly on the next refresh now that it re-fetches
    /// subprojects from the server each time, but this avoids waiting on
    /// that round trip. Guards against double-adding in case `load()` already
    /// refreshed by the time this runs.
    public func addSubproject(_ project: Project) {
        guard !subprojects.contains(where: { $0.id == project.id }) else { return }
        subprojects.append(ProjectNode(project: project))
        subprojectTaskSummaries[project.id] = TaskSummary(done: 0, total: 0)
    }

    /// Queues deletion of this screen's project or saved filter. The local
    /// repository hides it immediately and removes its cached row after the
    /// server confirms the request; the caller pops back once the local
    /// operation is accepted, mirroring `TaskDetailViewModel.deleteTask()`.
    @discardableResult
    public func deleteProject() async -> Bool {
        do {
            if let filterID = project.savedFilterID {
                try await filterRepository.deleteFilter(id: filterID)
                toastPresenter.show(String(localized: "Filter deleted", bundle: .module), style: .success)
            } else {
                try await projectRepository.delete(id: project.id)
                toastPresenter.show(String(localized: "Project deleted", bundle: .module), style: .success)
            }
            return true
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
            return false
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
            return false
        }
    }

    /// Builds a `DuplicateTaskViewModel` for `task`, seeded with this
    /// screen's own `project` — every task in `tasks` belongs to it, mirroring
    /// `TaskDetailViewModel.makeDuplicateTaskViewModel()`.
    public func makeDuplicateTaskViewModel(for task: VikunjaTask) -> DuplicateTaskViewModel {
        DuplicateTaskViewModel(
            source: task,
            sourceProject: project,
            taskRepository: repository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )
    }

    /// Observation can reorder or remove a row while a write is suspended.
    /// Apply the result only if that same optimistic value is still visible.
    private func acceptMutationResult(_ result: VikunjaTask, replacing expected: VikunjaTask) {
        guard let index = tasks.firstIndex(where: { $0.id == expected.id }), tasks[index] == expected else { return }
        tasks[index] = result
    }

    public func start() async {
        await synchronization.start(reload: { await self.load() }, onInitialFailure: { message in
            toastPresenter.show(message, style: .error)
        })
    }

    public func observeLocalChanges() async {
        await synchronization.observe { await self.load() }
    }

    public func refresh() async {
        await synchronization.refresh(reload: { await self.load() })
    }
}
