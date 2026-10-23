import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Renames a saved filter - the one field this app lets you change on one.
/// Goes through `FilterRepositoryProtocol`, never `ProjectRepositoryProtocol`
/// (`EditProjectViewModel`'s repository) - see that protocol's doc comment
/// for why there's no color or parent project to edit here.
@MainActor
@Observable
public final class RenameFilterViewModel {
    public var title: String
    public private(set) var isSaving = false
    public private(set) var saveErrorMessage: String?

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private let project: Project
    private let repository: FilterRepositoryProtocol
    private let toastPresenter: ToastPresenting

    public init(project: Project, repository: FilterRepositoryProtocol, toastPresenter: ToastPresenting) {
        self.project = project
        self.repository = repository
        self.toastPresenter = toastPresenter
        self.title = project.title
    }

    @discardableResult
    public func save() async -> Bool {
        guard canSave, let filterID = project.savedFilterID else { return false }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await repository.renameFilter(
                id: filterID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            )
            toastPresenter.show(String(localized: "Filter renamed", bundle: .module), style: .success)
            return true
        } catch let error as VikunjaError {
            saveErrorMessage = error.displayMessage
            return false
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
