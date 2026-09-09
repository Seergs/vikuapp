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
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Each project's own task-completion tally, keyed by project id, for the
    /// per-row progress indicator. Populated after the tree itself loads (a
    /// separate request per project), so a row simply shows no progress bar
    /// until its entry arrives or if the project has no tasks.
    public private(set) var taskSummaries: [Int: ProjectTaskSummary] = [:]

    public var isLoading: Bool {
        loadState == .loading
    }

    private let repository: ProjectRepositoryProtocol
    private let taskRepository: TaskRepositoryProtocol
    private let toastPresenter: ToastPresenting

    public init(
        repository: ProjectRepositoryProtocol,
        taskRepository: TaskRepositoryProtocol,
        toastPresenter: ToastPresenting,
    ) {
        self.repository = repository
        self.taskRepository = taskRepository
        self.toastPresenter = toastPresenter
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
            rootNodes = Self.tree(from: projects)
            loadState = .loaded
            taskSummaries = await Self.fetchTaskSummaries(for: rootNodes, repository: taskRepository)
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Deletes a project server-side, then drops it — and its whole subtree —
    /// from the local list. Vikunja cascades the delete to child projects and
    /// their tasks, so the entire node is removed here rather than reparenting
    /// its children. On failure the tree is left untouched and the error is
    /// surfaced as a toast.
    public func deleteProject(_ node: ProjectNode) async {
        do {
            try await repository.delete(id: node.id)
            rootNodes = Self.removing(node.id, from: rootNodes)
            for id in Self.flattenedIDs(of: [node]) {
                taskSummaries[id] = nil
            }
            toastPresenter.show("Project deleted", style: .success)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    /// Removes the node with `id` wherever it sits in the tree, pruning its
    /// descendants along with it.
    private static func removing(_ id: Int, from nodes: [ProjectNode]) -> [ProjectNode] {
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
                    guard let tasks = try? await repository.fetchTasks(projectID: id) else { return nil }
                    return (id, ProjectTaskSummary(done: tasks.filter(\.isDone).count, total: tasks.count))
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

    private static func flattenedIDs(of nodes: [ProjectNode]) -> [Int] {
        nodes.flatMap { [$0.id] + flattenedIDs(of: $0.children) }
    }

    /// Builds the parent/child tree for every non-archived project, ordered
    /// by `position` within each level. Guards against a cyclic
    /// `parentProjectID` (malformed server data) by never revisiting a
    /// project id on the same branch.
    static func tree(from projects: [Project]) -> [ProjectNode] {
        let visible = projects.filter { !$0.isArchived }
        let childrenByParentID = Dictionary(grouping: visible, by: \.parentProjectID)

        func nodes(withParentID parentID: Int?, excluding ancestorIDs: Set<Int>) -> [ProjectNode] {
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
