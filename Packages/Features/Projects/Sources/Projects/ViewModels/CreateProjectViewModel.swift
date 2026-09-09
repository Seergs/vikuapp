import Observation
import VikunjaCore
import VikuUI

/// Drives the "create project" sheet: title, color, and parent project
/// (defaulting to "None" — a root-level project). `parentProjectID` starts at
/// whatever the caller passed in at construction (set when the sheet is
/// opened from within a project's overview, to preset that project as the
/// parent) but stays user-editable via the picker, matching `Tasks`'
/// `QuickAddTaskViewModel`'s project picker.
@MainActor
@Observable
public final class CreateProjectViewModel {
    public var title: String = ""
    public var hexColor: String = ""
    public var parentProjectID: Int?
    public private(set) var projects: [Project] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    public private(set) var isSaving: Bool = false
    public private(set) var saveErrorMessage: String?

    public var isLoading: Bool {
        loadState == .loading
    }

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    public var selectedParentProject: Project? {
        guard let parentProjectID else { return nil }
        return projects.first { $0.id == parentProjectID }
    }

    private let repository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting

    public init(
        parentProjectID: Int? = nil,
        repository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
    ) {
        self.parentProjectID = parentProjectID
        self.repository = repository
        self.toastPresenter = toastPresenter
    }

    /// Loads the existing projects the parent-project picker offers.
    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            projects = try await repository.fetchProjects()
                .filter { !$0.isArchived }
                .sorted { $0.position < $1.position }
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Creates the project from the current form state. Leaves the form
    /// untouched on success so the caller (the sheet) decides what happens
    /// next — typically dismissing.
    @discardableResult
    public func save() async -> Project? {
        guard canSave else { return nil }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let created = try await repository.create(
                Project(
                    id: 0,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    parentProjectID: parentProjectID,
                    hexColor: hexColor,
                ),
            )
            toastPresenter.show("Project created", style: .success)
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
