import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the Home tab: either the account's tasks across every project,
/// grouped/filtered by due date (the "Today" digest), or — when the user has
/// pinned a project/saved filter in Settings — that single project/filter's
/// own tasks instead, both rendered by `TodayView`. Unlike `Projects`'
/// screens, the digest case has no single project scoping the fetch — every
/// project's tasks are pulled and merged here.
@MainActor
@Observable
public final class TodayViewModel {
    public private(set) var tasks: [VikunjaTask] = []
    /// Looked up per row for the project color dot + name, since a task only
    /// carries its `projectID`.
    public private(set) var projectsByID: [Int: Project] = [:]
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// The pinned project/saved filter, or `nil` for the default "Today"
    /// digest. Seeded from `homeSelectionCache` at init so `title` resolves
    /// instantly, then kept in sync with the server by every `load()` —
    /// including clearing it back to `nil` if the pin no longer exists (see
    /// `load()`).
    public private(set) var pinnedSelection: CachedHomeSelection?
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

    /// The screen title: the pinned selection's name, or the localized
    /// "Today" when nothing is pinned. The tab's own label stays "Home"
    /// regardless (`AppTab.title`) — only the in-screen title changes.
    public var title: String {
        pinnedSelection?.title ?? String(localized: "Today", bundle: .module)
    }

    public var datedTaskCount: Int {
        tasks.filter { $0.dueDate != nil }.count
    }

    public var pendingSubtitle: String {
        let pending = tasks.filter { $0.dueDate != nil && !$0.isDone }.count
        return String(localized: "\(pending) tasks pending", bundle: .module)
    }

    private let taskLoader: AccountTaskLoader
    private let mutator: TaskListMutator
    private let taskRepository: TaskRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting
    private let homeSelectionCache: HomeSelectionCaching

    public init(
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
        homeSelectionCache: HomeSelectionCaching = NoopHomeSelectionCaching(),
    ) {
        self.taskLoader = AccountTaskLoader(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
        )
        self.mutator = TaskListMutator(
            repository: taskRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
            errorMessage: { ($0 as? VikunjaError)?.displayMessage ?? $0.localizedDescription },
        )
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.labelRepository = labelRepository
        self.relationRepository = relationRepository
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
        self.homeSelectionCache = homeSelectionCache
        self.pinnedSelection = homeSelectionCache.cachedHomeSelection()
    }

    /// Skips the `.loading` transition when there's already loaded content
    /// (i.e. this is a pull-to-refresh): swapping the list out for a
    /// spinner mid-refresh would tear down the `List` that owns the
    /// in-flight `.refreshable` task, cancelling its request underneath it.
    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            if let pinned = homeSelectionCache.cachedHomeSelection() {
                try await loadPinned(pinned)
            } else {
                pinnedSelection = nil
                try await loadDigest()
            }
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    private func loadDigest() async throws {
        let result = try await taskLoader.loadAllTasks()
        projectsByID = result.projectsByID
        tasks = result.tasks
    }

    /// Loads `pinned`'s own tasks via `fetchTasks(projectID:)`, verified to
    /// resolve a saved filter's negative id to that filter's conditions
    /// server-side, the same call a real project's id makes.
    ///
    /// Re-validates the pin against a fresh `fetchProjects()` first, since
    /// the pinned project/filter can have been deleted since it was chosen:
    /// if it's gone, the pin is cleared, a one-time warning toast fires, and
    /// this falls back to the Today digest instead of leaving the screen
    /// stuck trying to fetch a project that no longer exists. If it's still
    /// there but renamed/recolored, the cache is refreshed to match so the
    /// Settings row and this screen's title stay current.
    private func loadPinned(_ pinned: CachedHomeSelection) async throws {
        let projects = try await projectRepository.fetchProjects()
        guard let current = projects.first(where: { $0.id.remoteValue == pinned.id }) else {
            homeSelectionCache.setCachedHomeSelection(nil)
            pinnedSelection = nil
            toastPresenter.show(
                String(
                    localized: "\"\(pinned.title)\" is no longer available. Showing Today instead.",
                    bundle: .module,
                ),
                style: .error,
            )
            try await loadDigest()
            return
        }

        let refreshed = CachedHomeSelection(
            id: current.id.remoteValue ?? pinned.id, title: current.title, hexColor: current.hexColor,
            kind: current.kind,
        )
        if refreshed != pinned {
            homeSelectionCache.setCachedHomeSelection(refreshed)
        }
        pinnedSelection = refreshed
        // Keyed by the server id, for looking up a task's project by
        // `task.projectID.remoteValue`. A project without one yet
        // (offline-created, not synced) is excluded — there's nothing to
        // key it by until it syncs.
        projectsByID = Dictionary(
            uniqueKeysWithValues: projects.compactMap { project in
                project.id.remoteValue.map { ($0, project) }
            },
        )
        tasks = try await taskRepository.fetchTasks(projectID: .remote(pinned.id))
    }

    /// Flips a task's completion state, persists the change, and rolls the
    /// local flip back if the server rejects it — so a failed request never
    /// leaves the row showing a state the server doesn't actually have.
    public func toggleDone(_ task: VikunjaTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var flipped = task
        flipped.isDone.toggle()
        tasks[index] = flipped
        tasks[index] = await mutator.persistToggleDone(flipped: flipped, original: task)
    }

    /// Sets a task's priority, persists the change, and rolls the local edit
    /// back if the server rejects it - mirrors `toggleDone(_:)`.
    public func setPriority(_ task: VikunjaTask, to priority: VikunjaTask.Priority) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.priority = priority
        tasks[index] = updated
        tasks[index] = await mutator.persistSetPriority(updated: updated, original: task)
    }

    /// Sets (or clears, via `nil`) a task's due date, persists the change,
    /// and rolls the local edit back if the server rejects it - mirrors
    /// `setPriority(_:to:)`. Clearing the date doesn't need to drop the row
    /// explicitly: `TodaySection.sections(from:filter:)` already excludes
    /// undated tasks, so the row disappears on the next re-render.
    public func setDueDate(_ task: VikunjaTask, to dueDate: Date?) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.dueDate = dueDate
        tasks[index] = updated
        tasks[index] = await mutator.persistSetDueDate(updated: updated, original: task)
    }

    /// Adds or removes `label` from `task`, persists the change, and rolls
    /// the local edit back if the server rejects it - mirrors
    /// `setPriority(_:to:)`. Task labels are read-only through the plain
    /// task update endpoint, so this routes through the label repository
    /// rather than `mutator.persistSetPriority`'s `repository.update(_:)`.
    public func toggleLabel(_ task: VikunjaTask, _ label: Label) async {
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
        tasks[index] = await mutator.persistToggleLabel(
            updated: updated, original: original, label: label, isAdding: isAdding, labelRepository: labelRepository,
        )
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
        let results = await (try? taskRepository.searchTasks(query: query)) ?? []
        relationSearchResults = results.filter { !excludedIDs.contains($0.id) }
    }

    /// Populates `relationSearchResults` with `task`'s own project's other
    /// tasks before the user has typed anything - mirrors
    /// `TaskDetailViewModel.loadRelationSuggestions()`.
    public func loadRelationSuggestions(for task: VikunjaTask) async {
        let excludedIDs = relatedTaskIDs(of: task)
        let results = await (try? taskRepository.fetchTasks(projectID: task.projectID)) ?? []
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
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let original = tasks[index]
        var updated = original
        updated.addRelation(relation, kind: kind)
        tasks[index] = updated
        tasks[index] = await mutator.persistAddRelation(
            relation, kind: kind, updated: updated, original: original, relationRepository: relationRepository,
        )
    }

    /// Deletes a task from the server and drops it from the local list on
    /// success. Vikunja soft-deletes tasks server-side rather than cascading
    /// the delete to subtasks/relations, so nothing else in the tree needs
    /// updating here.
    public func delete(_ task: VikunjaTask) async {
        if await mutator.delete(task) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    /// Loads every project on the instance, for the "Move to Project"
    /// picker. Failures leave `allProjects` at whatever it already was.
    public func loadMoveCandidates() async {
        allProjects = await (try? projectRepository.fetchProjects())?.realProjectsOnly() ?? allProjects
    }

    /// Moves `task` to `destination` and drops it from the local list on
    /// success — it no longer belongs to the Today view after the move.
    public func move(_ task: VikunjaTask, to destination: Project) async {
        if await mutator.move(task, to: destination) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    /// Builds a `DuplicateTaskViewModel` for `task`, resolving its project
    /// from `projectsByID` — falls back to a bare `Project` seeded from
    /// `task.projectID` on the off chance the lookup misses (`load()` always
    /// populates both from the same fetch, so this is only a defensive
    /// fallback), mirroring `TaskDetailViewModel.makeDuplicateTaskViewModel()`.
    public func makeDuplicateTaskViewModel(for task: VikunjaTask) -> DuplicateTaskViewModel {
        let sourceProject = task.projectID.remoteValue.flatMap { projectsByID[$0] } ?? Project(
            id: task.projectID, title: "",
        )
        return DuplicateTaskViewModel(
            source: task,
            sourceProject: sourceProject,
            taskRepository: taskRepository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )
    }
}
