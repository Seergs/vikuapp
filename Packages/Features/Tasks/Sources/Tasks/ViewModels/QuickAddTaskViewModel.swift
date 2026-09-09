import Observation
import VikunjaCore
import VikuUI

/// Drives the quick-add sheet: title + project + priority only, matching the
/// design mockup's `AddTaskSheet` (no due date/labels/assignee yet). The sheet
/// is presented globally from the tab bar's floating action button, so it
/// picks its starting project from context: `preselectedProjectID` when the
/// visible screen is a specific project (see `QuickAddContextTracking`),
/// otherwise `accountDefaultProjectID` — the user's Vikunja default project,
/// cached on device by `AppContainer` and refreshed once per app launch, so
/// opening this sheet never hits the network for it. `canSave` stays false
/// until a project is resolved or the user picks one.
@MainActor
@Observable
public final class QuickAddTaskViewModel {
    public var title: String = ""
    public var selectedProjectID: Int?
    private let preselectedProjectID: Int?
    private let accountDefaultProjectID: Int?
    public var priority: VikunjaTask.Priority = .unset
    public private(set) var projects: [Project] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    public private(set) var isSaving: Bool = false
    public private(set) var saveErrorMessage: String?

    public var isLoading: Bool {
        loadState == .loading
    }

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedProjectID != nil && !isSaving
    }

    public var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    private let taskRepository: TaskRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting

    /// - Parameters:
    ///   - preselectedProjectID: the project to start on when the sheet was
    ///     opened from a screen scoped to one project.
    ///   - accountDefaultProjectID: the account's cached Vikunja default
    ///     project, used when `preselectedProjectID` is `nil`. Both `nil`
    ///     leaves the sheet with no project until the user picks one.
    public init(
        preselectedProjectID: Int? = nil,
        accountDefaultProjectID: Int? = nil,
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
    ) {
        self.preselectedProjectID = preselectedProjectID
        self.accountDefaultProjectID = accountDefaultProjectID
        self.selectedProjectID = preselectedProjectID
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.toastPresenter = toastPresenter
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            projects = try await projectRepository.fetchProjects()
                .filter { !$0.isArchived }
                .sorted { $0.position < $1.position }
            // Fall back to the account default only if nothing was
            // preselected and that default is one of the projects just
            // loaded — a stale/inaccessible cached id is ignored rather than
            // left showing as a broken selection.
            if preselectedProjectID == nil,
               let accountDefaultProjectID,
               projects.contains(where: { $0.id == accountDefaultProjectID }) {
                selectedProjectID = accountDefaultProjectID
            }
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Creates the task from the current form state. Leaves `title`/
    /// `selectedProjectID`/`priority` untouched on success so the caller
    /// (the sheet) decides what happens next — typically dismissing.
    @discardableResult
    public func save() async -> VikunjaTask? {
        guard canSave, let selectedProjectID else { return nil }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let created = try await taskRepository.create(
                VikunjaTask(
                    id: 0,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    priority: priority,
                    projectID: selectedProjectID,
                ),
            )
            toastPresenter.show("Task created", style: .success)
            return created
        } catch let error as VikunjaError {
            saveErrorMessage = error.displayMessage
            return nil
        } catch {
            saveErrorMessage = error.localizedDescription
            return nil
        }
    }
}
