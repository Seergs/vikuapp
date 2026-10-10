import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Default Project" row in Settings' General section: lets the
/// user change which project new tasks default into (`User.defaultProjectID`
/// on the Vikunja server), presented via `ProjectPickerSheet`.
@MainActor
@Observable
public final class DefaultProjectSettingsViewModel {
    public private(set) var projects: [Project] = []
    public private(set) var defaultProjectID: Int?
    public private(set) var loadState: ScreenLoadState<Void> = .idle

    public var isLoading: Bool {
        loadState == .loading
    }

    /// The default project's display name, or `nil` when none is set — the
    /// row falls back to a localized "None" subtitle in that case.
    public var defaultProjectTitle: String? {
        guard let defaultProjectID else { return nil }
        return projects.first { $0.id == defaultProjectID }?.title
    }

    private let userRepository: UserRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let defaultProjectCache: DefaultProjectCaching
    private let toastPresenter: ToastPresenting

    public init(
        userRepository: UserRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        defaultProjectCache: DefaultProjectCaching,
        toastPresenter: ToastPresenting,
    ) {
        self.userRepository = userRepository
        self.projectRepository = projectRepository
        self.defaultProjectCache = defaultProjectCache
        self.toastPresenter = toastPresenter
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            async let fetchedProjects = projectRepository.fetchProjects()
            async let currentUser = userRepository.fetchCurrentUser()
            projects = try await fetchedProjects
            defaultProjectID = try await currentUser.defaultProjectID
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Commits the picker's selection. Optimistic, with rollback on failure —
    /// matches `NotificationsViewModel`'s toast-on-failure convention. Also
    /// refreshes `defaultProjectCache` so quick-add's instant preselection
    /// doesn't show the stale default until its next once-per-launch refresh.
    public func selectDefaultProject(_ project: Project?) async {
        let previous = defaultProjectID
        defaultProjectID = project?.id
        do {
            let updated = try await userRepository.updateDefaultProject(id: project?.id)
            defaultProjectID = updated.defaultProjectID
            defaultProjectCache.setCachedDefaultProject(
                project.map { CachedDefaultProject(id: $0.id, title: $0.title, hexColor: $0.hexColor) },
            )
        } catch let error as VikunjaError {
            defaultProjectID = previous
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            defaultProjectID = previous
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }
}
