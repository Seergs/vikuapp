import Foundation
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
/// opening this sheet never hits the network for it. While `load()` is
/// validating that id against the freshly fetched project list, `displayProject`
/// shows the last known default from `defaultProjectCache` instead of a
/// spinner; `load()` rewrites that cache once it confirms the real one.
/// `canSave` stays false until a project is resolved or the user picks one.
@MainActor
@Observable
public final class QuickAddTaskViewModel {
    /// The raw text the user types. Shortcuts in it (`#Project`, `p1`, ...)
    /// are parsed by `QuickAddParser`. A matched project or priority is copied
    /// into `selectedProjectID` / `priority`, the same state the pickers edit.
    public var input: String = "" {
        didSet { syncShortcutsToPicker() }
    }

    /// The project the task is saved to: the picker's value, or the last matched shortcut.
    public var selectedProjectID: Int?
    private let preselectedProjectID: Int?
    private let accountDefaultProjectID: Int?
    private let defaultProjectCache: DefaultProjectCaching?
    /// Snapshotted once at init, not re-read later: the display cache only
    /// matters before `load()` resolves, and `load()` is the only thing that
    /// ever changes it afterwards.
    private let cachedDefaultProject: CachedDefaultProject?
    /// The priority the task is saved with: the chips' value, or the last shortcut.
    public var priority: VikunjaTask.Priority = .unset
    public private(set) var projects: [Project] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    public private(set) var isSaving: Bool = false
    public private(set) var saveErrorMessage: String?

    public var isLoading: Bool {
        loadState == .loading
    }

    /// `input` parsed with the user's syntax against the loaded projects and labels.
    public var parsed: QuickAddParser.Result {
        QuickAddParser.parse(input, projects: projects, labels: labels, syntax: syntax)
    }

    /// Shortcuts that get a chip: a project that matched nothing or several projects,
    /// a label that matched several labels, and a label that will be created on save.
    /// The pickers cannot show these, so the chips do.
    public var shortcutChips: [QuickAddParser.ResolvedToken] {
        parsed.tokens.filter { item in
            switch item.resolution {
            case .unmatchedProject, .ambiguousProject, .ambiguousLabel, .newLabel: true
            default: false
            }
        }
    }

    /// The user picked a project in the picker. Writes it into the text, so the
    /// title shows what will be saved. Replaces a `#`/`+` shortcut, or appends one.
    public func pickProject(_ project: Project?) {
        selectedProjectID = project?.id
        guard let syntax else { return }
        input = QuickAddParser.settingProject(project?.title, in: input, syntax: syntax)
    }

    /// The user picked a priority chip. Writes it into the text as a `p`/`!` shortcut.
    public func pickPriority(_ value: VikunjaTask.Priority) {
        priority = value
        guard let syntax else { return }
        input = QuickAddParser.settingPriority(value, in: input, syntax: syntax)
    }

    public var canSave: Bool {
        !parsed.title.isEmpty && selectedProjectID != nil && !isSaving
    }

    public var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    /// What the project field shows before `load()` resolves: the last known
    /// default project from the on-device cache, so the sheet never needs a
    /// spinner there. Only used when nothing was preselected — a preselected
    /// project has no cache to borrow from and briefly has nothing to show
    /// instead, same as before this existed. Never drives `selectedProjectID`/
    /// `canSave`; those still wait for `load()` to confirm the real default.
    public var displayProject: Project? {
        guard preselectedProjectID == nil, let cachedDefaultProject else { return nil }
        return Project(
            id: cachedDefaultProject.id,
            title: cachedDefaultProject.title,
            hexColor: cachedDefaultProject.hexColor,
        )
    }

    /// The raw text of the project and priority shortcuts last copied into the
    /// pickers. A shortcut is copied again only when its own text changes, so a
    /// manual pick made afterwards survives until the shortcut is edited.
    private var appliedProjectText: String?
    private var appliedPriorityText: String?

    private func syncShortcutsToPicker() {
        let result = parsed

        let projectText = result.tokens.first { $0.token.kind == .project }
            .map { String(input[$0.token.range]) }
        if projectText != appliedProjectText {
            appliedProjectText = projectText
            if let projectID = result.projectID {
                selectedProjectID = projectID
            }
        }

        let priorityText = result.tokens.first { $0.token.kind == .priority }
            .map { String(input[$0.token.range]) }
        if priorityText != appliedPriorityText {
            appliedPriorityText = priorityText
            if let level = result.priority {
                priority = level
            }
        }
    }

    /// `nil` when shortcuts are off, so the title and pickers behave as before.
    private var syntax: QuickAddSyntax? {
        syntaxStore?.syntax
    }

    private let taskRepository: TaskRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting
    /// Notified on a successful save so a project-scoped screen elsewhere
    /// (e.g. that project's overview) can refresh live instead of waiting for
    /// the next pull-to-refresh. Optional so tests and any caller that
    /// doesn't care can skip it.
    private let taskChangeBroadcaster: TaskChangeBroadcasting?
    /// The dialect the shortcuts are parsed with. Optional so tests can
    /// skip it; without it shortcuts are off.
    private let syntaxStore: QuickAddSyntaxStore?
    /// Creates and attaches labels. Optional so tests and callers without labels can skip it.
    private let labelRepository: LabelRepositoryProtocol?
    private var labels: [Label] = []
    /// False until the labels load, so a label typed before then is never created as "new" by mistake.
    private var labelsLoaded = false

    /// Labels can be used when there is a repository and its labels have loaded.
    private var labelsAvailable: Bool {
        labelRepository != nil && labelsLoaded
    }

    /// Color for labels created from the quick-add title: the first label swatch
    /// of Design System's `VikuColor.SwatchPalette`, which this ViewModel does not import.
    private static let newLabelHex = "6449A2"

    /// - Parameters:
    ///   - preselectedProjectID: the project to start on when the sheet was
    ///     opened from a screen scoped to one project.
    ///   - accountDefaultProjectID: the account's cached Vikunja default
    ///     project, used when `preselectedProjectID` is `nil`. Both `nil`
    ///     leaves the sheet with no project until the user picks one.
    ///   - defaultProjectCache: the on-device display cache `displayProject`
    ///     reads from and `load()` rewrites. `nil` for tests that don't care
    ///     about the optimistic display (it just leaves `displayProject` nil).
    public init(
        preselectedProjectID: Int? = nil,
        accountDefaultProjectID: Int? = nil,
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
        taskChangeBroadcaster: TaskChangeBroadcasting? = nil,
        syntaxStore: QuickAddSyntaxStore? = nil,
        labelRepository: LabelRepositoryProtocol? = nil,
        defaultProjectCache: DefaultProjectCaching? = nil,
    ) {
        self.preselectedProjectID = preselectedProjectID
        self.accountDefaultProjectID = accountDefaultProjectID
        self.selectedProjectID = preselectedProjectID
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.toastPresenter = toastPresenter
        self.taskChangeBroadcaster = taskChangeBroadcaster
        self.syntaxStore = syntaxStore
        self.labelRepository = labelRepository
        self.defaultProjectCache = defaultProjectCache
        self.cachedDefaultProject = defaultProjectCache?.cachedDefaultProject()
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
               let matchedDefault = projects.first(where: { $0.id == accountDefaultProjectID }) {
                selectedProjectID = accountDefaultProjectID
                let fresh = CachedDefaultProject(
                    id: matchedDefault.id,
                    title: matchedDefault.title,
                    hexColor: matchedDefault.hexColor,
                )
                if fresh != cachedDefaultProject {
                    defaultProjectCache?.setCachedDefaultProject(fresh)
                }
            } else if preselectedProjectID == nil, cachedDefaultProject != nil {
                // The account has no default anymore, or its cached project
                // is gone (deleted/archived) — drop the stale optimistic cache.
                defaultProjectCache?.setCachedDefaultProject(nil)
            }
            if let labelRepository {
                // A label failure must not fail the whole sheet: the projects and
                // priority still work, and `save()` refuses label shortcuts instead.
                do {
                    labels = try await labelRepository.fetchLabels()
                    labelsLoaded = true
                } catch {
                    labelsLoaded = false
                }
            }
            // A project shortcut typed before the list arrived was unmatched
            // then, so copy it again now that the projects are known.
            appliedProjectText = nil
            syncShortcutsToPicker()
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Creates the task from the current form state. Leaves `input`/
    /// `selectedProjectID`/`priority` untouched on success so the caller
    /// (the sheet) decides what happens next — typically dismissing.
    ///
    /// Order: labels named in the title that don't exist yet are created first,
    /// then the task, then every label is attached. If creating a label fails,
    /// no task is made. If attaching one fails, the task still exists, so the
    /// user is told rather than the sheet staying open to create a duplicate.
    @discardableResult
    public func save() async -> VikunjaTask? {
        guard canSave, let projectID = selectedProjectID else { return nil }
        let shortcut = parsed
        let usesLabels = shortcut.tokens.contains { $0.token.kind == .label }
        if usesLabels, !labelsAvailable {
            saveErrorMessage = String(
                localized: "Labels aren't available right now. Try again once they load.",
                bundle: .module,
            )
            return nil
        }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let newLabelIDs = try await createLabels(named: shortcut.newLabelNames)
            let created = try await taskRepository.create(
                VikunjaTask(
                    id: 0,
                    title: shortcut.title,
                    priority: priority,
                    projectID: projectID,
                ),
            )
            let failedAttachments = await attachLabels(shortcut.labelIDs + newLabelIDs, to: created.id)
            if failedAttachments == 0 {
                toastPresenter.show(String(localized: "Task created", bundle: .module), style: .success)
            } else {
                toastPresenter.show(
                    String(localized: "Task created, but some labels couldn't be added", bundle: .module),
                    style: .error,
                )
            }
            taskChangeBroadcaster?.taskCreated(projectID: projectID)
            return created
        } catch let error as VikunjaError {
            saveErrorMessage = error.displayMessage
            return nil
        } catch {
            saveErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func createLabels(named names: [String]) async throws -> [Int] {
        guard let labelRepository else { return [] }
        var ids: [Int] = []
        for name in names {
            let created = try await labelRepository.create(Label(id: 0, title: name, hexColor: Self.newLabelHex))
            ids.append(created.id)
        }
        return ids
    }

    /// Attaches each label and returns how many failed. Each attach is independent,
    /// so one failure does not skip the rest.
    private func attachLabels(_ labelIDs: [Int], to taskID: Int) async -> Int {
        guard let labelRepository else { return 0 }
        var failures = 0
        for labelID in labelIDs {
            do {
                try await labelRepository.addLabel(labelID, toTask: taskID)
            } catch {
                failures += 1
            }
        }
        return failures
    }
}
