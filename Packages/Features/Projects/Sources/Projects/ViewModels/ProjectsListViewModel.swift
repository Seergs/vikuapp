import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the projects list screen: loads the flat project list from the
/// server and arranges it into a parent/child tree by `parentProjectID`,
/// ready for a hierarchical view to render.
@MainActor
@Observable
public final class ProjectsListViewModel {
    public private(set) var rootNodes: [ProjectNode] = []
    /// Favorites (if present) followed by saved filters, flat (neither kind
    /// nests), kept apart from `rootNodes` so the view can render them in
    /// their own "Favorites & Filters" section above "My Projects" instead
    /// of mixed into the real project tree.
    public private(set) var pseudoNodes: [ProjectNode] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Each project's own task-completion tally, keyed by project id, for the
    /// per-row progress indicator. Seeded from `taskSummaryCache` so rows show
    /// their last known counts immediately instead of a redacted placeholder,
    /// then replaced wholesale once the tree loads and each project's own
    /// (separate) count request resolves.
    public private(set) var taskSummaries: [Int: ProjectTaskSummary] = [:]

    public var isLoading: Bool {
        loadState == .loading
    }

    private let repository: ProjectRepositoryProtocol
    private let taskRepository: TaskRepositoryProtocol
    /// Only consulted when a node being deleted is a saved filter -
    /// `deleteProject(_:)` goes through this, never `repository`, since a
    /// filter's real id isn't the negative pseudo-project id `/projects`
    /// hands back. See `FilterRepositoryProtocol`.
    private let filterRepository: FilterRepositoryProtocol
    private let taskSummaryCache: ProjectTaskSummaryCaching
    private let toastPresenter: ToastPresenting

    public init(
        repository: ProjectRepositoryProtocol,
        taskRepository: TaskRepositoryProtocol,
        filterRepository: FilterRepositoryProtocol,
        taskSummaryCache: ProjectTaskSummaryCaching,
        toastPresenter: ToastPresenting,
    ) {
        self.repository = repository
        self.taskRepository = taskRepository
        self.filterRepository = filterRepository
        self.taskSummaryCache = taskSummaryCache
        self.toastPresenter = toastPresenter
        self.taskSummaries = taskSummaryCache.cachedTaskSummaries().mapValues {
            ProjectTaskSummary(done: $0.done, total: $0.total)
        }
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
            let projects = try await repository.fetchProjects()
            rootNodes = Self.tree(from: projects.realProjectsOnly())
            pseudoNodes = Self.pseudoNodes(from: projects)
            loadState = .loaded
            let fetched = await Self.fetchTaskSummaries(for: rootNodes + pseudoNodes, repository: taskRepository)
            taskSummaries = fetched
            taskSummaryCache.setCachedTaskSummaries(
                fetched.mapValues { CachedProjectTaskSummary(done: $0.done, total: $0.total) },
            )
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Deletes a project (or, for a saved filter, the filter itself - through
    /// `filterRepository`, never `repository`, see its doc comment) server-
    /// side, then drops it from the local list. Vikunja cascades a project
    /// delete to child projects and their tasks, so the entire node is
    /// removed here rather than reparenting its children. A saved filter has
    /// no children to reparent either way - it's a flat entry in
    /// `pseudoNodes`. On failure the list is left untouched and the error is
    /// surfaced as a toast.
    public func deleteProject(_ node: ProjectNode) async {
        do {
            if let filterID = node.project.savedFilterID {
                try await filterRepository.deleteFilter(id: filterID)
                pseudoNodes.removeAll { $0.id == node.id }
                if let remoteID = node.id.remoteValue {
                    taskSummaries[remoteID] = nil
                }
                toastPresenter.show(String(localized: "Filter deleted", bundle: .module), style: .success)
            } else {
                try await repository.delete(id: node.id)
                rootNodes = Self.removing(node.id, from: rootNodes)
                for id in Self.flattenedIDs(of: [node]) {
                    if let remoteID = id.remoteValue {
                        taskSummaries[remoteID] = nil
                    }
                }
                toastPresenter.show(String(localized: "Project deleted", bundle: .module), style: .success)
            }
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    /// Removes the node with `id` wherever it sits in the tree, pruning its
    /// descendants along with it.
    private static func removing(_ id: EntityID, from nodes: [ProjectNode]) -> [ProjectNode] {
        nodes.compactMap { node in
            guard node.id != id else { return nil }
            return ProjectNode(project: node.project, children: removing(id, from: node.children))
        }
    }

    /// Fetches every project's own task list concurrently so each row can show
    /// a real completion count. A project whose fetch fails is left out rather
    /// than failing the whole screen — its row just shows no progress bar.
    private static func fetchTaskSummaries(
        for nodes: [ProjectNode],
        repository: TaskRepositoryProtocol,
    ) async -> [Int: ProjectTaskSummary] {
        let ids = flattenedIDs(of: nodes)
        return await withTaskGroup(of: (Int, ProjectTaskSummary)?.self) { group in
            for id in ids {
                group.addTask {
                    // The returned dictionary is keyed by remote id (for
                    // callers that only ever look a project up by one), so a
                    // node without a synced id yet (offline-created) has
                    // nowhere to store its summary - it just shows no badge
                    // until it syncs, even though `fetchTasks(projectID:)`
                    // itself can resolve its locally-created tasks fine.
                    guard let remoteID = id.remoteValue,
                          let tasks = try? await repository.fetchTasks(projectID: id) else { return nil }
                    return (remoteID, ProjectTaskSummary(done: tasks.filter(\.isDone).count, total: tasks.count))
                }
            }
            var summaries: [Int: ProjectTaskSummary] = [:]
            for await result in group {
                if let (id, summary) = result {
                    summaries[id] = summary
                }
            }
            return summaries
        }
    }

    private static func flattenedIDs(of nodes: [ProjectNode]) -> [EntityID] {
        nodes.flatMap { [$0.id] + flattenedIDs(of: $0.children) }
    }

    /// Favorites (at most one, id always `-1`) followed by saved filters
    /// (ordered by `position`), each wrapped as a childless `ProjectNode` —
    /// neither pseudo-project kind can have children, see `ProjectKind`.
    private static func pseudoNodes(from projects: [Project]) -> [ProjectNode] {
        let favorites = projects.filter { $0.kind == .favorites }
        let filters = projects.filter { $0.kind == .savedFilter }.sorted { $0.position < $1.position }
        return (favorites + filters).map { ProjectNode(project: $0, children: []) }
    }

    /// Builds the parent/child tree for every non-archived project, ordered
    /// by `position` within each level. Guards against a cyclic
    /// `parentProjectID` (malformed server data) by never revisiting a
    /// project id on the same branch.
    static func tree(from projects: [Project]) -> [ProjectNode] {
        let visible = projects.filter { !$0.isArchived }
        let childrenByParentID = Dictionary(grouping: visible, by: \.parentProjectID)

        func nodes(withParentID parentID: EntityID?, excluding ancestorIDs: Set<EntityID>) -> [ProjectNode] {
            (childrenByParentID[parentID] ?? [])
                .sorted { $0.position < $1.position }
                .compactMap { project in
                    guard !ancestorIDs.contains(project.id) else { return nil }
                    let children = nodes(withParentID: project.id, excluding: ancestorIDs.union([project.id]))
                    return ProjectNode(project: project, children: children)
                }
        }

        return nodes(withParentID: nil, excluding: [])
    }
}
