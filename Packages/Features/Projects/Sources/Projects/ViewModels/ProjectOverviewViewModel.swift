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
    public let bulkSelection: TaskBulkSelection
    public let overdueRescheduler: OverdueRescheduler
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
    /// Account-local owners of tasks in a saved filter. Retained if a catalog read fails.
    public private(set) var projectsByID: [EntityID: Project] = [:]

    public func project(for task: VikunjaTask) -> Project? {
        if project.kind == .project, project.id == task.projectID {
            return project
        }
        return projectsByID[task.projectID]
    }

    /// Keep detail and duplication attached to the real owner even when its metadata is unavailable.
    public func taskProject(for task: VikunjaTask) -> Project {
        project(for: task) ?? Project(id: task.projectID, title: "")
    }

    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Reachability state drives the saved-filter snapshot notice. Regular
    /// projects and Favorites don't need to expose the filter-query caveat.
    public private(set) var isOffline = false
    /// Runtime API-v2 support or an already downloaded board enables Kanban
    /// for projects and saved filters. Saved filters also require confirmed connectivity;
    /// Favorites have no Kanban view.
    public var supportsKanban: Bool {
        hasKanbanSupport && (project.kind != .savedFilter || (hasReachability && !isOffline))
    }

    private var hasKanbanSupport = false
    private var hasReachability = false
    /// This saved filter's raw query (e.g. `priority >= 3 && done = false`).
    /// `nil` for a real project or
    /// Favorites, and also `nil` if the fetch fails or the filter has no
    /// query set - either way the query line just doesn't render, no error
    /// banner for what's a nice-to-have display. See `SavedFilterDetail`.
    public private(set) var savedFilterQuery: String?
    /// Read-only presentation resolved from account-local catalogs. Missing
    /// projects or labels retain their IDs; the raw query is never rewritten.
    public var savedFilterDisplayQuery: String? {
        savedFilterQuery == nil ? nil : savedFilterDisplaySegments.map(\.text).joined()
    }

    public private(set) var savedFilterDisplaySegments: [FilterQueryFormatter.Segment] = []
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
    public private(set) var labelCatalog = LabelCatalog(labels: [])
    public var allLabels: [Label] {
        labelCatalog.labels
    }

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
    private let bulkUpdateRepository: TaskBulkUpdateRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private var hasRequestedLabels = false
    private var labelCatalogVersion = 0
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
    private var completionState = TaskCompletionState()

    /// Finish an individual local write before allowing a bulk selection.
    var hasPendingCompletionWrites: Bool {
        completionState.hasPendingChanges
    }

    public init(
        syncTrigger: SyncTriggering,
        localData: LocalDataObserving,
        project: Project,
        subprojects: [ProjectNode] = [],
        repository: TaskRepositoryProtocol,
        bulkUpdateRepository: TaskBulkUpdateRepositoryProtocol,
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
        self.bulkSelection = TaskBulkSelection(toastPresenter: toastPresenter)
        self.overdueRescheduler = OverdueRescheduler(toastPresenter: toastPresenter)
        self.synchronization = LocalScreenSync(
            trigger: syncTrigger, localData: localData, toastPresenter: toastPresenter,
        )
        self.project = project
        self.subprojects = subprojects
        self.repository = repository
        self.bulkUpdateRepository = bulkUpdateRepository
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

    /// Keeps the offline notice and saved-filter Kanban availability in step with connectivity while this screen
    /// is visible. The view owns the task so SwiftUI cancels the stream when
    /// the screen disappears.
    public func observeReachability() async {
        for await isReachable in await reachabilityUpdates() {
            isOffline = !isReachable
            hasReachability = true
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
                project: fetchedProject, repository: projectRepository,
            )
            let summaries = await Self.fetchSubprojectSummaries(fetchedSubprojects, repository: repository)
            let catalog = fetchedProject.kind == .savedFilter
                ? try? await projectRepository.fetchProjects() : nil
            let owners = catalog.map { Dictionary(
                $0.realProjectsOnly().map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest },
            ) } ?? projectsByID
            let query = await loadFilterQuery(for: fetchedProject, projects: Array(owners.values))
            await loadRequestedLabels()
            guard version == loadVersion, !Task.isCancelled else { return }
            project = fetchedProject
            projectsByID = owners
            tasks = completionState.applying(to: fetchedTasks)
            subprojects = fetchedSubprojects
            subprojectTaskSummaries = summaries
            savedFilterQuery = query.raw
            savedFilterDisplaySegments = query.segments
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
        hasKanbanSupport = project.kind != .favorites && serverSupportsKanban
    }

    private func resolveKanbanSupport() async -> Bool {
        guard project.kind != .favorites else { return false }
        if let kanbanRepository, await (try? kanbanRepository.hasCachedKanbanSupport()) == true {
            return true
        }
        return await capabilityProvider.supports(.apiV2)
    }

    private func loadFilterQuery(for project: Project, projects: [Project]) async -> (raw: String?, segments: [FilterQueryFormatter.Segment]) {
        guard let filterID = project.savedFilterID,
              let query = try? await filterRepository.fetchFilter(id: filterID).query,
              !query.isEmpty else { return (nil, []) }
        return await (query, resolveFilterNames(query, projects: projects))
    }

    /// Catalog reads use the injected offline repositories. Each catalog can
    /// fail independently without hiding names available in the other one.
    private func resolveFilterNames(_ query: String, projects: [Project]) async -> [FilterQueryFormatter.Segment] {
        async let labels = try? labelRepository.fetchLabels()
        let projectTitles = projects.reduce(into: [Int: String]()) { titles, project in
            if let id = project.id.remoteValue {
                titles[id] = project.title
            }
        }
        let labelTitles = await (labels ?? []).reduce(into: [Int: String]()) { titles, label in
            if let id = label.id.remoteValue {
                titles[id] = label.title
            }
        }
        return FilterQueryFormatter.displaySegments(
            query, labelTitle: { labelTitles[$0] }, projectTitle: { projectTitles[$0] },
        )
    }

    /// This project's current direct children, straight from the server —
    /// mirrors `ProjectsListViewModel.tree(from:)`'s own filtering (drop
    /// archived, order by position) but only one level deep, since this
    /// screen only ever shows direct children as "Subprojects" cards.
    private static func fetchSubprojects(
        project: Project,
        repository: ProjectRepositoryProtocol,
    ) async throws -> [ProjectNode] {
        // Virtual projects cannot have children. A filter's catalog is only
        // needed for names, so its failure must not fail the whole screen.
        guard project.kind == .project else { return [] }
        return try await repository.fetchProjects()
            .filter { !$0.isArchived && $0.parentProjectID == project.id }
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
        guard !bulkSelection.isSelecting, !bulkSelection.isPerformingAction else { return }
        guard let index = tasks.firstIndex(where: { $0.id == task.id }),
              tasks[index].isDone == task.isDone else { return }
        let original = tasks[index]
        guard let flipped = completionState.begin(original) else { return }
        loadVersion += 1
        tasks[index] = flipped
        let result = await mutator.persistToggleDone(flipped: flipped, original: original)
        // A read started before the local write finished may still contain
        // the old completion value, even after its pending overlay is removed.
        loadVersion += 1
        completionState.resolve(result, in: &tasks)
    }

    /// Sets a task's priority, persists the change, and rolls the local edit
    /// back if the server rejects it - mirrors `toggleDone(_:)`.
    public func setPriority(_ task: VikunjaTask, to priority: VikunjaTask.Priority) async {
        guard let original = await taskForMutation(task) else { return }
        loadVersion += 1
        var updated = original
        updated.priority = priority
        replaceVisibleTask(updated)
        let result = await mutator.persistSetPriority(updated: updated, original: original)
        acceptMutationResult(result, replacing: updated)
    }

    /// Sets (or clears, via `nil`) a task's due date, persists the change,
    /// and rolls the local edit back if the server rejects it - mirrors
    /// `setPriority(_:to:)`.
    public func setDueDate(_ task: VikunjaTask, to dueDate: Date?) async {
        guard let original = await taskForMutation(task) else { return }
        loadVersion += 1
        var updated = original
        updated.dueDate = dueDate
        replaceVisibleTask(updated)
        let result = await mutator.persistSetDueDate(updated: updated, original: original)
        acceptMutationResult(result, replacing: updated)
    }

    /// Adds or removes `label` from `task`, persists the change, and rolls
    /// the local edit back if the server rejects it - mirrors
    /// `setPriority(_:to:)`. Task labels are read-only through the plain
    /// task update endpoint, so this routes through the label repository
    /// rather than `mutator.persistSetPriority`'s `repository.update(_:)`.
    public func toggleLabel(_ task: VikunjaTask, _ label: Label) async {
        _ = await persistLabelToggle(task, label)
    }

    private func persistLabelToggle(_ task: VikunjaTask, _ label: Label) async -> VikunjaTask? {
        guard let original = await taskForMutation(task) else { return nil }
        let label = labelCatalog.canonicalLabel(label)
        loadVersion += 1
        var updated = original
        let isAdding = !updated.labels.contains { labelCatalog.canonicalID(for: $0.id) == label.id }
        if isAdding {
            updated.labels.append(label)
        } else {
            updated.labels.removeAll { labelCatalog.canonicalID(for: $0.id) == label.id }
        }
        replaceVisibleTask(updated)
        let result = await mutator.persistToggleLabel(
            updated: updated, original: original, label: label, isAdding: isAdding, labelRepository: labelRepository,
        )
        acceptMutationResult(result, replacing: updated)
        return result
    }

    /// Loads every label on the instance, for the label picker sheet.
    /// Failures leave `allLabels` at whatever it already was, mirroring
    /// `loadMoveCandidates()`.
    public func loadAllLabels() async {
        hasRequestedLabels = true
        labelCatalogVersion += 1
        let version = labelCatalogVersion
        if let catalog = try? await labelRepository.fetchLabelCatalog(), version == labelCatalogVersion {
            labelCatalog = catalog
        }
    }

    private func loadRequestedLabels() async {
        if hasRequestedLabels {
            await loadAllLabels()
        }
    }

    /// Creates a new label on the instance and attaches it to `task` -
    /// mirrors `TaskDetailViewModel.createAndAddLabel(title:hexColor:)`.
    @discardableResult
    public func createAndAddLabel(_ task: VikunjaTask, title: String, hexColor: String) async -> Label? {
        guard let created = try? await labelRepository.create(Label(id: 0, title: title, hexColor: hexColor)) else {
            return nil
        }
        labelCatalogVersion += 1
        labelCatalog.labels.append(created)
        let result = await persistLabelToggle(task, created)
        await loadAllLabels()
        let canonical = labelCatalog.canonicalLabel(created)
        let attached = result?.labels.contains {
            labelCatalog.canonicalID(for: $0.id) == canonical.id
        } ?? false
        return attached ? canonical : nil
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
        guard let original = await taskForMutation(task) else { return }
        loadVersion += 1
        var updated = original
        updated.addRelation(relation, kind: kind)
        replaceVisibleTask(updated)
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

    public func setSelectedCompletion(isDone: Bool, visibleTasks: [VikunjaTask]) async {
        guard !completionState.hasPendingChanges else { return }
        await bulkSelection.setCompletion(visibleTasks: visibleTasks, isDone: isDone) { selected in
            loadVersion += 1
            let updated = try await bulkUpdateRepository.setCompletion(taskIDs: selected.map(\.id), isDone: isDone)
            loadVersion += 1
            for task in updated {
                guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
                // Local observations may refresh other fields while the write is pending.
                tasks[index].isDone = task.isDone
            }
            if isDone {
                hapticPresenter.play(.success)
            }
        }
    }

    /// Moves every overdue task the list shows to the end of today or
    /// tomorrow in one bulk write. Waits for pending individual completion
    /// writes, like bulk completion, and is unavailable while selecting.
    public func rescheduleOverdue(_ overdueTasks: [VikunjaTask], to shortcut: DueDateShortcut) async {
        guard !completionState.hasPendingChanges, !bulkSelection.isSelecting else { return }
        await overdueRescheduler.reschedule(overdueTasks, to: shortcut) { ids, dueDate in
            loadVersion += 1
            let updated = try await bulkUpdateRepository.setDueDate(taskIDs: ids, dueDate: dueDate)
            loadVersion += 1
            for task in updated {
                guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
                // Local observations may refresh other fields while the write is pending.
                tasks[index].dueDate = task.dueDate
            }
        }
    }

    /// Accepted local deletions disappear immediately; rejected items remain selected.
    public func deleteSelectedTasks(visibleTasks: [VikunjaTask]) async {
        loadVersion += 1
        await bulkSelection.delete(visibleTasks: visibleTasks) { task in
            guard await mutator.delete(task, showsFeedback: false) else { return false }
            loadVersion += 1
            tasks.removeAll { $0.id == task.id }
            return true
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

    /// Builds a duplicate using the task's owner rather than a saved filter's pseudo-project.
    public func makeDuplicateTaskViewModel(for task: VikunjaTask) -> DuplicateTaskViewModel {
        DuplicateTaskViewModel(
            source: task,
            sourceProject: taskProject(for: task),
            taskRepository: repository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )
    }

    /// A board's server-side filter can include tasks absent from the local list.
    /// Read those tasks through the canonical repository instead of silently ignoring
    /// their actions or adding them to a list whose filter they may not satisfy.
    private func taskForMutation(_ task: VikunjaTask) async -> VikunjaTask? {
        guard !Task.isCancelled else { return nil }
        if let current = tasks.first(where: { $0.id == task.id }) {
            return current
        }
        do {
            let fetched = try await repository.fetchTask(id: task.id)
            guard !Task.isCancelled else { return nil }
            return tasks.first(where: { $0.id == task.id }) ?? fetched
        } catch is CancellationError {
            return nil
        } catch {
            toastPresenter.show((error as? VikunjaError)?.displayMessage ?? error.localizedDescription, style: .error)
            return nil
        }
    }

    private func replaceVisibleTask(_ task: VikunjaTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
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
        await synchronization.observe {
            if self.hasRequestedLabels {
                await self.loadAllLabels()
            }
            await self.load()
        }
    }

    public func refresh() async {
        await synchronization.refresh(reload: { await self.load() })
    }
}
