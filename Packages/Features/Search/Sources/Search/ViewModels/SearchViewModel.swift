import Foundation
import Observation
import VikunjaCore
import VikuUI

@Observable
@MainActor
public final class SearchViewModel {
    /// Avoid recalculating and rendering results for every keystroke.
    static let debounceInterval: Duration = .milliseconds(300)

    private let searchRepository: TaskSearchRepositoryProtocol
    private let syntaxStore: QuickAddSyntaxStore?
    private let projectRepository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let mutator: TaskListMutator

    var query = ""
    var state = ScreenLoadState<[VikunjaTask]>.idle
    var projectsByID: [EntityID: Project] = [:]

    private var lastSearchQuery = ""
    private var lastSearchSyntax: QuickAddSyntax?
    private(set) var searchTask: Task<Void, Never>?

    var syntax: QuickAddSyntax? {
        syntaxStore?.syntax
    }

    var searchHint: String {
        switch syntax {
        case .vikunja:
            String(localized: "Search by title, or use `*Label`, `+Project` and `!3`", bundle: .module)
        case .todoist:
            String(localized: "Search by title, or use `@Label`, `#Project` and `p1`", bundle: .module)
        case nil:
            String(localized: "Type a query to search all your tasks", bundle: .module)
        }
    }

    public func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        if state.isLoading {
            state = .idle
        }
    }

    /// Whether the account's project list has been fetched at least once this
    /// view-model lifetime. Projects only feed each row's name/color badge and
    /// barely change during a search session, so the list is fetched once and
    /// reused instead of re-downloaded on every debounced search.
    private var projectsLoaded = false

    /// Set once the "could not load project details" toast has been shown, so a
    /// burst of searches against a failing `/projects` endpoint doesn't queue
    /// one identical error toast per keystroke. Reset on the next success.
    private var didWarnProjectLoadFailure = false

    public init(
        taskRepository: TaskRepositoryProtocol,
        searchRepository: TaskSearchRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
        syntaxStore: QuickAddSyntaxStore? = nil,
    ) {
        self.searchRepository = searchRepository
        self.syntaxStore = syntaxStore
        self.projectRepository = projectRepository
        self.toastPresenter = toastPresenter
        self.mutator = TaskListMutator(
            repository: taskRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
            errorMessage: { ($0 as? VikunjaError)?.displayMessage ?? $0.localizedDescription },
        )
    }

    /// Called on every change to `query`. Debounces, then searches.
    public func queryChanged() {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.isEmpty {
            searchTask = nil
            lastSearchQuery = ""
            state = .idle
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmedQuery)
        }
    }

    /// Warms the project cache when the Search screen appears, so the first
    /// search doesn't have to wait on the project list at all.
    public func preload() async {
        await loadProjects()
        // Resume an unfinished search cancelled when leaving the screen. Loaded
        // results deliberately do not observe edits or synchronization yet.
        if !Task.isCancelled, searchTask == nil, !state.isLoaded,
           !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryChanged()
        }
    }

    private func performSearch(_ trimmedQuery: String) async {
        let syntax = syntax
        guard trimmedQuery != lastSearchQuery || syntax != lastSearchSyntax || !state.isLoaded else { return }

        // Keep the current results on screen while re-searching; only fall back
        // to the full-screen spinner when there's nothing to show yet. This is
        // what stops the list from flickering away on every keystroke.
        if !state.isLoaded {
            state = .loading
        }

        do {
            // Project badges load concurrently with the local task query.
            async let projectsReady: Void = loadProjects()
            let criteria = QuickAddParser.searchQuery(trimmedQuery, syntax: syntax)
            let tasks = try await searchRepository.searchTasks(matching: criteria)
            guard !Task.isCancelled else { return }
            await projectsReady
            guard !Task.isCancelled else { return }

            // A task pointing at a project created since the list was cached:
            // refresh once so its row can render instead of being dropped by
            // the `if let project` lookup in the view.
            if tasks.contains(where: { projectsByID[$0.projectID] == nil }) {
                await loadProjects(force: true)
                guard !Task.isCancelled else { return }
            }

            // Only advance `lastSearchQuery` once the search actually landed, so
            // a cancelled or failed query can be retried instead of being
            // suppressed by the dedupe guard above while stale results show.
            lastSearchQuery = trimmedQuery
            lastSearchSyntax = syntax
            state = .loaded(tasks)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failure(
                (error as? VikunjaError)?.displayMessage ?? String(localized: "Search failed", bundle: .module),
            )
        }
    }

    /// Flips a task's completion state optimistically, persists it, and rolls
    /// the flip back if the server rejects it — same semantics as every other
    /// task-list screen (`TaskListMutator`). `state` is re-read after the
    /// request so a search that landed new results mid-toggle isn't clobbered.
    public func toggleDone(_ task: VikunjaTask) async {
        guard case var .loaded(tasks) = state,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var flipped = task
        flipped.isDone.toggle()
        tasks[index] = flipped
        state = .loaded(tasks)

        let resolved = await mutator.persistToggleDone(flipped: flipped, original: task)
        guard case var .loaded(current) = state,
              let currentIndex = current.firstIndex(where: { $0.id == task.id }) else { return }
        current[currentIndex] = resolved
        state = .loaded(current)
    }

    public func delete(_ task: VikunjaTask) async {
        guard await mutator.delete(task) else { return }
        if case var .loaded(tasks) = state {
            tasks.removeAll { $0.id == task.id }
            state = .loaded(tasks)
        }
    }

    /// Fetches the account's project list into `projectsByID`. A no-op once the
    /// list has been loaded, unless `force` is set (used when a search result
    /// references a project the cache hasn't seen yet).
    private func loadProjects(force: Bool = false) async {
        guard force || !projectsLoaded else { return }
        do {
            let projects = try await projectRepository.fetchProjects()
            projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            projectsLoaded = true
            didWarnProjectLoadFailure = false
        } catch {
            guard !Task.isCancelled else { return }
            if !didWarnProjectLoadFailure {
                toastPresenter.show(String(localized: "Could not load project details", bundle: .module), style: .error)
                didWarnProjectLoadFailure = true
            }
        }
    }
}
