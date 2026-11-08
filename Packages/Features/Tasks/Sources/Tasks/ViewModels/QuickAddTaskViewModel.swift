import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the quick-add sheet's title, project, and priority fields, plus
/// label and due-date shortcuts interpreted from the title. Raw input remains
/// editable; saving uses the cleaned title and uniquely resolved due instant.
/// The sheet is presented globally from the tab bar's floating action button, so it
/// picks its starting project from context: `preselectedProjectID` when the
/// visible screen is a specific project (see `QuickAddContextTracking`),
/// otherwise `accountDefaultProjectID` — the user's Vikunja default project,
/// cached on device by `AppContainer` and refreshed once per app launch, so
/// opening this sheet never hits the network for it. While `load()` is
/// validating that id against the freshly fetched project list, `displayProject`
/// shows a project instead of a spinner: `preselectedProject` (the full object
/// the preselecting screen already had in hand, see `QuickAddContextTracking`)
/// when there is one, otherwise the last known default from
/// `defaultProjectCache`. `load()` rewrites that cache once it confirms the
/// real default. `canSave` stays false until a project is resolved or the
/// user picks one.
@MainActor
@Observable
public final class QuickAddTaskViewModel {
    /// The raw text the user types. Shortcuts in it (`#Project`, `p1`, ...)
    /// are parsed by `QuickAddParser`. A matched project or priority is copied
    /// into `selectedProjectID` / `priority`, the same state the pickers edit.
    public var input: String = "" {
        didSet {
            if !isApplyingDueDate, hasRelativeReminder, dueDate == nil,
               (parseInput(oldValue).dueDate ?? pickedDueDate) != nil {
                pendingDueDateRemoval = .input(input)
                input = oldValue
                isConfirmingDueDateRemoval = true
                return
            }
            // A newly typed, uniquely resolved date supersedes a picker choice.
            // Ordinary title/project/priority edits leave that choice intact.
            if parsed.dueDate != nil {
                pickedDueDate = nil
            }
            syncShortcutsToPicker()
            labelSelectionOrder = selectedLabels.map(\.id)
            updateRelativeReminder()
        }
    }

    private var pickedDueDate: Date?
    private var isApplyingDueDate = false
    private enum DueDateRemoval {
        case picker
        case input(String)
    }

    private var pendingDueDateRemoval: DueDateRemoval?
    public private(set) var reminder: TaskReminder?
    public private(set) var isConfirmingDueDateRemoval = false

    private var hasRelativeReminder: Bool {
        reminder?.relativeTo == .dueDate
    }

    /// Quick Add supports one reminder. A new picker choice replaces it;
    /// relative reminders always have a valid due-date anchor in this draft.
    public func setReminder(_ value: TaskReminder?) {
        if let relation = value?.relativeTo {
            guard relation == .dueDate, dueDate != nil else { return }
        }
        cancelDueDateRemoval()
        reminder = value
        updateRelativeReminder()
    }

    public func confirmDueDateRemoval() {
        guard let pending = pendingDueDateRemoval else { return }
        cancelDueDateRemoval()
        reminder = nil
        switch pending {
        case .picker: applyDueDate(nil)
        case let .input(proposed): input = proposed
        }
    }

    public func cancelDueDateRemoval() {
        pendingDueDateRemoval = nil
        isConfirmingDueDateRemoval = false
    }

    private func updateRelativeReminder() {
        guard hasRelativeReminder, let dueDate, var value = reminder else { return }
        // Resolve the unsaved draft locally; Vikunja remains authoritative
        // once the task exists and its dates are changed by synchronization.
        value.reminder = dueDate.addingTimeInterval(TimeInterval(value.relativePeriod))
        reminder = value
    }

    /// The single date used by both the chip and task creation. Picker dates
    /// remain exact instants; they are never formatted and parsed back from text.
    public var dueDate: Date? {
        parsed.dueDate ?? pickedDueDate
    }

    /// A picker choice (including removal) replaces an applied date in the
    /// input, keeping all other text and shortcuts. Unresolved/literal phrases
    /// stay untouched. A later typed date can take over again.
    public func pickDueDate(_ date: Date?) {
        if date == nil, dueDate != nil, hasRelativeReminder {
            pendingDueDateRemoval = .picker
            isConfirmingDueDateRemoval = true
            return
        }
        cancelDueDateRemoval()
        applyDueDate(date)
    }

    private func applyDueDate(_ date: Date?) {
        isApplyingDueDate = true
        defer { isApplyingDueDate = false }
        let interpretation = parsed.dateInterpretation
        if interpretation.resolvedDate != nil, let expression = interpretation.expressions.first {
            var range = expression.range
            if range.lowerBound > input.startIndex,
               input[input.index(before: range.lowerBound)].isWhitespace {
                range = input.index(before: range.lowerBound) ..< range.upperBound
            }
            var updated = input
            updated.removeSubrange(range)
            input = updated.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        pickedDueDate = date
        updateRelativeReminder()
    }

    /// The project the task is saved to: the picker's value, or the last matched shortcut.
    public var selectedProjectID: EntityID?
    private let preselectedProjectID: EntityID?
    /// The full project a preselecting screen already had in hand, kept only
    /// when its id matches `preselectedProjectID` (a caller that resolved the
    /// two independently, e.g. a `viku://quick-add?project=` deep link against
    /// a mismatched on-screen scope, drops it rather than show the wrong one).
    private let preselectedProject: Project?
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
        parseInput(input)
    }

    private func parseInput(_ value: String) -> QuickAddParser.Result {
        QuickAddParser.parse(value, projects: projects, labels: labels, syntax: syntax, dateContext: dateParsingContext)
    }

    /// The app supplies the device zone captured when this sheet opens.
    /// Snapshotting context keeps relative dates stable throughout this editing session,
    /// including failed saves and retries. Synchronization receives the resolved instant.
    public let dateParsingContext: NaturalLanguageDateParser.Context
    private let datePreviewStore: QuickAddDatePreviewStoring?

    public var isDatePreviewEnabled: Bool {
        syntax != nil && datePreviewStore?.isQuickAddDatePreviewVisible == true
    }

    public var datePreview: NaturalLanguageDateParser.Result {
        parsed.dateInterpretation
    }

    /// Date styling and saving share the same interpretation, independently of the Developer panel.
    var titleHighlights: QuickAddTitleHighlights {
        let result = parsed
        var spans = result.tokens.map {
            QuickAddTitleHighlights.Span(range: $0.token.range, style: .shortcut($0.resolution))
        }
        let dates = result.dateInterpretation
        if dates.resolvedDate != nil, let expression = dates.expressions.first {
            spans.append(.init(range: expression.range, style: .date))
        }
        return QuickAddTitleHighlights(input: input, spans: spans)
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
        !parsed.title.isEmpty && selectedProjectID != nil && !isSaving && !isConfirmingDueDateRemoval
    }

    public var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    /// What the project field shows before `load()` resolves, so the sheet
    /// never needs a spinner there: `preselectedProject` when the preselecting
    /// screen handed one over, otherwise the last known default project from
    /// the on-device cache (only when nothing was preselected — a preselected
    /// id with no matching `preselectedProject`, e.g. a mismatched deep link,
    /// briefly has nothing to show instead, same as before either of these
    /// existed). Never drives `selectedProjectID`/`canSave`; those still wait
    /// for `load()` to confirm the real project.
    public var displayProject: Project? {
        if let preselectedProject {
            return preselectedProject
        }
        guard preselectedProjectID == nil, let cachedDefaultProject else { return nil }
        return Project(
            id: .remote(cachedDefaultProject.id),
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
                selectedProjectID = .remote(projectID)
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
    public private(set) var labelCatalog = LabelCatalog(labels: [])
    public private(set) var labelsLoadState: ScreenLoadState<Void> = .idle
    private var pickedLabels: [Label] = []
    private var labelSelectionOrder: [EntityID] = []
    private var labels: [Label] {
        labelCatalog.labels
    }

    public var canPickLabels: Bool {
        labelRepository != nil
    }

    /// Labels retain their selection order, once per identity. Reading
    /// resolved label models retains unsynced IDs that `parsed.labelIDs` omits.
    public var selectedLabels: [Label] {
        let typed = parsed.tokens.compactMap { item -> Label? in
            if case let .label(label) = item.resolution {
                return label
            }
            return nil
        }
        let selected = (pickedLabels + typed).map(labelCatalog.canonicalLabel)
        let ordered = labelSelectionOrder.compactMap { id in
            selected.first { $0.id == labelCatalog.canonicalID(for: id) }
        }
        var seen: Set<EntityID> = []
        return (ordered + selected).filter { seen.insert($0.id).inserted }
    }

    public func toggleLabel(_ label: Label) {
        let canonical = labelCatalog.canonicalLabel(label)
        guard selectedLabels.contains(where: { $0.id == canonical.id }) else {
            guard labelsAvailable else { return }
            pickedLabels.append(canonical)
            labelSelectionOrder = selectedLabels.map(\.id)
            return
        }
        pickedLabels.removeAll { labelCatalog.canonicalID(for: $0.id) == canonical.id }
        // Removing a selected label must also remove all its applied shortcuts,
        // otherwise the next input edit would silently select it again.
        let ranges = parsed.tokens.compactMap { item -> Range<String.Index>? in
            guard case let .label(value) = item.resolution,
                  labelCatalog.canonicalID(for: value.id) == canonical.id else { return nil }
            return item.token.range
        }
        guard !ranges.isEmpty else {
            labelSelectionOrder = selectedLabels.map(\.id)
            return
        }
        var updated = input
        for var range in ranges.reversed() {
            if range.lowerBound > updated.startIndex,
               updated[updated.index(before: range.lowerBound)].isWhitespace {
                range = updated.index(before: range.lowerBound) ..< range.upperBound
            }
            updated.removeSubrange(range)
        }
        input = updated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func loadLabels() async {
        guard let labelRepository, labelsLoadState != .loading else { return }
        let previousState = labelsLoadState
        labelsLoadState = .loading
        do {
            labelCatalog = try await labelRepository.fetchLabelCatalog()
            pickedLabels = pickedLabels.map(labelCatalog.canonicalLabel)
            labelSelectionOrder = selectedLabels.map(\.id)
            labelsLoadState = .loaded
        } catch is CancellationError {
            labelsLoadState = previousState
        } catch let error as VikunjaError {
            labelsLoadState = .failure(error.displayMessage)
        } catch {
            labelsLoadState = .failure(error.localizedDescription)
        }
    }

    /// Labels can be used when there is a repository and its labels have loaded.
    private var labelsAvailable: Bool {
        labelRepository != nil && labelsLoadState == .loaded
    }

    /// Color for labels created from the quick-add title: the first label swatch
    /// of Design System's `VikuColor.SwatchPalette`, which this ViewModel does not import.
    private static let newLabelHex = "6449A2"

    /// - Parameters:
    ///   - preselectedProjectID: the project to start on when the sheet was
    ///     opened from a screen scoped to one project.
    ///   - preselectedProject: the full project behind `preselectedProjectID`,
    ///     when the caller has it in hand (see `QuickAddContextTracking`).
    ///     Ignored if its id doesn't match `preselectedProjectID`.
    ///   - accountDefaultProjectID: the account's cached Vikunja default
    ///     project, used when `preselectedProjectID` is `nil`. Both `nil`
    ///     leaves the sheet with no project until the user picks one.
    ///   - defaultProjectCache: the on-device display cache `displayProject`
    ///     reads from and `load()` rewrites. `nil` for tests that don't care
    ///     about the optimistic display (it just leaves `displayProject` nil).
    public init(
        preselectedProjectID: EntityID? = nil,
        preselectedProject: Project? = nil,
        accountDefaultProjectID: Int? = nil,
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
        taskChangeBroadcaster: TaskChangeBroadcasting? = nil,
        syntaxStore: QuickAddSyntaxStore? = nil,
        labelRepository: LabelRepositoryProtocol? = nil,
        defaultProjectCache: DefaultProjectCaching? = nil,
        datePreviewStore: QuickAddDatePreviewStoring? = nil,
        dateParsingContext: NaturalLanguageDateParser.Context = .init(
            referenceDate: Date(), timeZone: .current, languages: [.spanish, .english],
        ),
    ) {
        self.preselectedProjectID = preselectedProjectID
        self.preselectedProject = preselectedProject?.id == preselectedProjectID ? preselectedProject : nil
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
        self.dateParsingContext = dateParsingContext
        self.datePreviewStore = datePreviewStore
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            projects = try await projectRepository.fetchProjects()
                .filter { !$0.isArchived }
                .realProjectsOnly()
                .sorted { $0.position < $1.position }
            // Fall back to the account default only if nothing was
            // preselected and that default is one of the projects just
            // loaded — a stale/inaccessible cached id is ignored rather than
            // left showing as a broken selection.
            if preselectedProjectID == nil,
               let accountDefaultProjectID,
               let matchedDefault = projects.first(where: { $0.id.remoteValue == accountDefaultProjectID }) {
                selectedProjectID = .remote(accountDefaultProjectID)
                let fresh = CachedDefaultProject(
                    id: accountDefaultProjectID,
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
            // Label failures stay independent of project loading.
            await loadLabels()
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
        let selectedDueDate = dueDate
        let selectedReminders = reminder.map { [$0] } ?? []
        let selectedLabelIDs = selectedLabels.map(\.id)
        let usesLabels = shortcut.tokens.contains { $0.token.kind == .label }
        if usesLabels || !selectedLabelIDs.isEmpty, !labelsAvailable {
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
                    dueDate: selectedDueDate,
                    priority: priority,
                    projectID: projectID,
                    reminders: selectedReminders,
                ),
            )
            var seen: Set<EntityID> = []
            let labelIDs = (selectedLabelIDs + newLabelIDs).filter { seen.insert($0).inserted }
            let failedAttachments = await attachLabels(labelIDs, to: created.id)
            // Only available when the project list has already loaded (see
            // `canSave`'s doc comment) - the toast just isn't tappable in
            // that edge case rather than guessing at a `Project` value.
            let action = projects.first { $0.id == projectID }.map { ToastAction.taskDetail(created, $0) }
            if failedAttachments == 0 {
                toastPresenter.show(String(localized: "Task created", bundle: .module), style: .success, action: action)
            } else {
                toastPresenter.show(
                    String(localized: "Task created, but some labels couldn't be added", bundle: .module),
                    style: .error,
                    action: action,
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

    private func createLabels(named names: [String]) async throws -> [EntityID] {
        guard let labelRepository else { return [] }
        var ids: [EntityID] = []
        for name in names {
            let created = try await labelRepository.create(Label(id: 0, title: name, hexColor: Self.newLabelHex))
            ids.append(created.id)
        }
        return ids
    }

    /// Attaches each label and returns how many failed. Each attach is independent,
    /// so one failure does not skip the rest.
    private func attachLabels(_ labelIDs: [EntityID], to taskID: EntityID) async -> Int {
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
