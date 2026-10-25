import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Home Screen" row in Settings' Connection section: lets the
/// user pin a project or saved filter as the Home tab's content instead of
/// the default Today digest, presented via `HomeSelectionPickerSheet`.
///
/// Purely local — unlike `DefaultProjectSettingsViewModel`, there's no
/// server-side value behind the pin, so `select(_:)` has nothing to roll
/// back and `load()` only needs to fetch the picker's project list.
@MainActor
@Observable
public final class HomeSelectionSettingsViewModel {
    public private(set) var projects: [Project] = []
    public private(set) var selection: CachedHomeSelection?
    public private(set) var loadState: ScreenLoadState<Void> = .idle

    public var isLoading: Bool {
        loadState == .loading
    }

    /// The picker's offering: real projects and saved filters, never
    /// Favorites (a derived view over tasks that already live elsewhere,
    /// not a pinnable destination in its own right — same reasoning as
    /// `AccountTaskLoader`'s exclusion) or archived projects.
    public var pickableProjects: [Project] {
        projects.filter { $0.kind != .favorites && !$0.isArchived }
    }

    /// The pinned selection's display title, or the localized "Today" when
    /// nothing is pinned.
    public var selectionTitle: String {
        selection?.title ?? String(localized: "Today", bundle: .module)
    }

    private let projectRepository: ProjectRepositoryProtocol
    private let store: HomeSelectionCaching

    public init(projectRepository: ProjectRepositoryProtocol, store: HomeSelectionCaching) {
        self.projectRepository = projectRepository
        self.store = store
        self.selection = store.cachedHomeSelection()
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            projects = try await projectRepository.fetchProjects()
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Commits the picker's selection. `nil` pins "Today" (clears the pin).
    public func select(_ project: Project?) {
        // Not reachable until Projects' own offline-create path exists — a
        // project without a synced id yet can't be pinned.
        let newSelection = project.flatMap { project in
            project.id.remoteValue.map {
                CachedHomeSelection(id: $0, title: project.title, hexColor: project.hexColor, kind: project.kind)
            }
        }
        selection = newSelection
        store.setCachedHomeSelection(newSelection)
    }
}
