import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the Today screen: the account's tasks across every project,
/// grouped/filtered by due date in `TodayView`. Unlike `Projects`' screens,
/// there's no single project scoping the fetch — every project's tasks are
/// pulled and merged here.
@MainActor
@Observable
public final class TodayViewModel {
    public private(set) var tasks: [VikunjaTask] = []
    /// Looked up per row for the project color dot + name, since a task only
    /// carries its `projectID`.
    public private(set) var projectsByID: [Int: Project] = [:]
    public private(set) var loadState: ScreenLoadState<Void> = .idle
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

    public var datedTaskCount: Int {
        tasks.filter { $0.dueDate != nil }.count
    }

    public var pendingSubtitle: String {
        let pending = tasks.filter { $0.dueDate != nil && !$0.isDone }.count
        return pending == 1 ? "1 task pending" : "\(pending) tasks pending"
    }

    private let taskLoader: AccountTaskLoader
    private let mutator: TaskListMutator
    private let taskRepository: TaskRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting

    public init(
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
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
            let result = try await taskLoader.loadAllTasks()
            projectsByID = result.projectsByID
            tasks = result.tasks
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
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
    private func relatedTaskIDs(of task: VikunjaTask) -> Set<Int> {
        var ids = Set(task.dependsOn.map(\.id) + task.blocks.map(\.id))
        for relations in task.otherRelations.values {
            ids.formUnion(relations.map(\.id))
        }
        ids.insert(task.id)
        return ids
    }

    /// Adds `relation` under `kind` to `task` - mirrors
    /// `TaskDetailViewModel.addRelation(_:kind:)`, but this list doesn't
    /// render relations, so there's nothing to update locally.
    public func addRelation(_ relation: TaskRelation, kind: RelationKind, to task: VikunjaTask) async {
        await mutator.persistAddRelation(relation, kind: kind, to: task, relationRepository: relationRepository)
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
        allProjects = await (try? projectRepository.fetchProjects()) ?? allProjects
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
        DuplicateTaskViewModel(
            source: task,
            sourceProject: projectsByID[task.projectID] ?? Project(id: task.projectID, title: ""),
            taskRepository: taskRepository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )
    }
}
