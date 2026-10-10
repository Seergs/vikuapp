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
    /// The account's own IANA zone (`User.timezone`), shown read-only below
    /// the "Default Project" row — there's no editing flow for it yet. Seeded
    /// from `timezoneCache` so it shows the last known value immediately
    /// instead of disappearing while `load()` is in flight, then overwritten
    /// with whatever `load()` reports (`nil` if the user never set one).
    public private(set) var accountTimezone: String?

    public var isLoading: Bool {
        loadState == .loading
    }

    /// The default project's display name, or `nil` when none is known — the
    /// row falls back to a localized "None" subtitle in that case. Before
    /// `load()` resolves (including a failed load, so a transient error
    /// doesn't flash "None" over a real value), this is the last known title
    /// from `defaultProjectCache`; once it resolves, it's always the freshly
    /// fetched project's title.
    public var defaultProjectTitle: String? {
        guard loadState == .loaded else {
            return cachedDefaultProject?.title
        }
        guard let defaultProjectID else { return nil }
        return projects.first { $0.id == defaultProjectID }?.title
    }

    private let userRepository: UserRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let defaultProjectCache: DefaultProjectCaching
    private let timezoneCache: AccountTimezoneCaching
    private let toastPresenter: ToastPresenting
    /// Snapshotted once at init, like `QuickAddTaskViewModel.cachedDefaultProject` —
    /// only matters before `load()` resolves, and `load()` is the only thing
    /// that changes the on-device cache afterwards.
    private let cachedDefaultProject: CachedDefaultProject?

    public init(
        userRepository: UserRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        defaultProjectCache: DefaultProjectCaching,
        timezoneCache: AccountTimezoneCaching,
        toastPresenter: ToastPresenting,
    ) {
        self.userRepository = userRepository
        self.projectRepository = projectRepository
        self.defaultProjectCache = defaultProjectCache
        self.timezoneCache = timezoneCache
        self.toastPresenter = toastPresenter
        self.cachedDefaultProject = defaultProjectCache.cachedDefaultProject()
        self.accountTimezone = timezoneCache.cachedTimezone()
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            async let fetchedProjects = projectRepository.fetchProjects()
            async let currentUser = userRepository.fetchCurrentUser()
            projects = try await fetchedProjects
            let user = try await currentUser
            defaultProjectID = user.defaultProjectID
            accountTimezone = user.timezone
            if user.timezone != timezoneCache.cachedTimezone() {
                timezoneCache.setCachedTimezone(user.timezone)
            }
            let freshDefaultProject = defaultProjectID
                .flatMap { id in projects.first { $0.id == id } }
                .map { CachedDefaultProject(id: $0.id, title: $0.title, hexColor: $0.hexColor) }
            if freshDefaultProject != defaultProjectCache.cachedDefaultProject() {
                defaultProjectCache.setCachedDefaultProject(freshDefaultProject)
            }
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
