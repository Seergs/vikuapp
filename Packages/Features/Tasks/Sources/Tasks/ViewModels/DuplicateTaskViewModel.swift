import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "duplicate task" sheet.
///
/// Vikunja's own duplicate (2.2.0+, a single button that clones a task
/// verbatim) isn't used: it only exists on recent servers, and it gives the
/// user no chance to change anything first — the common case being renaming
/// the copy. This is a client-side duplicate instead. The sheet opens
/// pre-filled from the source task with every field still editable; on
/// confirm it creates a fresh task via `TaskRepositoryProtocol.create`, then
/// replays the source's labels and "Relations"-section relations through
/// their own endpoints (Vikunja accepts neither in the create body).
///
/// Not copied: subtasks (a subtask's parent is effectively singular in
/// Vikunja, so cloning those links would attach the same children to two
/// parents), comments, and attachments.
@MainActor
@Observable
public final class DuplicateTaskViewModel {
    public var title: String
    public var selectedProjectID: Int?
    public var priority: VikunjaTask.Priority
    public var copyLabels: Bool = true
    public var copyRelations: Bool = true

    public private(set) var projects: [Project] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    public private(set) var isSaving: Bool = false
    public private(set) var saveErrorMessage: String?

    private let source: VikunjaTask
    private let sourceProject: Project
    private let taskRepository: TaskRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting

    public var isLoading: Bool {
        loadState == .loading
    }

    /// Whether the source task carries anything the matching toggle would
    /// copy — the sheet hides a toggle that would do nothing.
    public var hasLabelsToCopy: Bool {
        !source.labels.isEmpty
    }

    public var hasRelationsToCopy: Bool {
        source.hasRelations
    }

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedProjectID != nil
            && !isSaving
    }

    public var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    public init(
        source: VikunjaTask,
        sourceProject: Project,
        taskRepository: TaskRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
    ) {
        self.source = source
        self.sourceProject = sourceProject
        self.title = Self.copyTitle(of: source.title)
        self.selectedProjectID = source.projectID
        self.priority = source.priority
        self.taskRepository = taskRepository
        self.labelRepository = labelRepository
        self.relationRepository = relationRepository
        self.projectRepository = projectRepository
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            projects = try await projectRepository.fetchProjects()
                .filter { !$0.isArchived }
                .sorted { $0.position < $1.position }
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Creates the duplicate from the current form state and copies the
    /// requested extras. Returns the created task together with its project
    /// (resolved from the loaded list, falling back to the source's project)
    /// so the caller can navigate straight to it. Leaves the form untouched
    /// on success so the caller (the sheet) decides what happens next.
    @discardableResult
    public func duplicate() async -> (task: VikunjaTask, project: Project)? {
        guard canSave, let selectedProjectID else { return nil }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let created = try await taskRepository.create(
                VikunjaTask(
                    id: 0,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: source.description,
                    dueDate: source.dueDate,
                    priority: priority,
                    projectID: selectedProjectID,
                ),
            )
            if copyLabels {
                await attachLabels(to: created.id)
            }
            if copyRelations {
                await attachRelations(to: created.id)
            }
            hapticPresenter.play(.success)
            toastPresenter.show("Task duplicated", style: .success)
            return (created, project(withID: created.projectID))
        } catch let error as VikunjaError {
            saveErrorMessage = error.displayMessage
            return nil
        } catch {
            saveErrorMessage = error.localizedDescription
            return nil
        }
    }

    /// The project the created task landed in — from the loaded list when
    /// available, otherwise the source task's own project (which the caller
    /// passed in and is the default selection), so there's always something
    /// to navigate to.
    private func project(withID id: Int) -> Project {
        projects.first { $0.id == id } ?? sourceProject
    }

    /// Best-effort: a label that fails to attach is skipped rather than
    /// failing the whole duplicate — the task itself is already created, and
    /// there's no partial state worth rolling back to.
    private func attachLabels(to taskID: Int) async {
        for label in source.labels {
            try? await labelRepository.addLabel(label.id, toTask: taskID)
        }
    }

    /// Replays the source's `dependsOn`/`blocks`/`otherRelations` — the
    /// "Relations" section as `TaskDetailView` shows it — pointing the copy
    /// at the same related tasks. Best-effort, like `attachLabels(to:)`.
    private func attachRelations(to taskID: Int) async {
        var work: [(kind: RelationKind, otherTaskID: Int)] = []
        work += source.dependsOn.map { (.blocked, $0.id) }
        work += source.blocks.map { (.blocking, $0.id) }
        for (kind, relations) in source.otherRelations {
            work += relations.map { (kind, $0.id) }
        }
        for item in work {
            try? await relationRepository.addRelation(kind: item.kind, otherTaskID: item.otherTaskID, toTask: taskID)
        }
    }

    /// `"Buy milk"` → `"Buy milk (copy)"`, and `"Buy milk (copy)"` →
    /// `"Buy milk (copy) (copy)"` is fine — it's only a starting point the
    /// user edits.
    private static func copyTitle(of title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? trimmed : "\(trimmed) (copy)"
    }
}
