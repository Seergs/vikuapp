import Observation
import VikunjaCore
import VikuUI

@MainActor
@Observable
public final class EditProjectViewModel {
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

    /// The project being edited — excluded (with its whole subtree) from the
    /// parent-project picker, since a project can't be reparented under
    /// itself or one of its descendants.
    public var editingProjectID: Int {
        project.id
    }

    private let project: Project
    private let repository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting

    public init(
        project: Project,
        repository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
    ) {
        self.project = project
        self.repository = repository
        self.toastPresenter = toastPresenter
        self.title = project.title
        self.hexColor = project.hexColor
        self.parentProjectID = project.parentProjectID
    }

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

    public func save() async -> Project? {
        guard canSave else { return nil }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await repository.update(
                Project(
                    id: project.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    parentProjectID: parentProjectID,
                    hexColor: hexColor,
                ),
            )
            toastPresenter.show("Project updated", style: .success)
            return updated
        } catch let error as VikunjaError {
            saveErrorMessage = error.displayMessage
            return nil
        } catch {
            saveErrorMessage = error.localizedDescription
            return nil
        }
    }
}
