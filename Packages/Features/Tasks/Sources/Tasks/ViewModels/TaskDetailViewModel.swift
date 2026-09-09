import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives a single task's detail screen. `task` starts as whatever was passed
/// in at navigation time (so the screen shows content immediately, no
/// blank/spinner flash) and `load()` refreshes it from the server.
@MainActor
@Observable
public final class TaskDetailViewModel {
    public let project: Project
    public private(set) var task: VikunjaTask
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Every label on the instance, for the label picker sheet to offer —
    /// loaded lazily via `loadAllLabels()` rather than alongside `load()`,
    /// since most task views are never opened.
    public private(set) var allLabels: [Label] = []
    /// Candidates for the "add relation" task picker, from the most recent
    /// `searchTasksForRelation(query:)` call.
    public private(set) var relationSearchResults: [VikunjaTask] = []
    /// Every project on the instance, for resolving a relation candidate's
    /// project name in the "add relation" task picker — loaded lazily via
    /// `loadAllProjects()` rather than alongside `load()`, the same reasoning
    /// as `allLabels`/`loadAllLabels()`.
    public private(set) var allProjects: [Project] = []
    /// This task's comments, oldest first (Vikunja's own order). Loaded via
    /// `loadComments()` rather than alongside `load()` — the detail screen
    /// kicks both off together, but keeping them separate means a comments
    /// failure doesn't block the rest of the screen from showing.
    public private(set) var comments: [TaskComment] = []
    public private(set) var commentsLoadState: ScreenLoadState<Void> = .idle
    /// This task's file attachments, in Vikunja's order (oldest first).
    /// Loaded via `loadAttachments()` on its own load state — same reasoning
    /// as `comments`: a failure here shouldn't blank the rest of the screen.
    public private(set) var attachments: [TaskAttachment] = []
    public private(set) var attachmentsLoadState: ScreenLoadState<Void> = .idle
    /// `true` while an upload request is in flight — the view disables the
    /// add affordance and shows a progress row.
    public private(set) var isUploadingAttachment = false

    public var isLoading: Bool {
        loadState == .loading
    }

    private let repository: TaskRepositoryProtocol
    private let labelRepository: LabelRepositoryProtocol
    private let relationRepository: TaskRelationRepositoryProtocol
    private let commentRepository: TaskCommentRepositoryProtocol
    private let attachmentRepository: TaskAttachmentRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting
    /// Set by `AppContainer` so a quick-add opened while this task is on
    /// screen defaults to the task's project. Optional so tests and any
    /// caller that doesn't care can skip it.
    private let quickAddContext: QuickAddContextTracking?

    public init(
        task: VikunjaTask,
        project: Project,
        repository: TaskRepositoryProtocol,
        labelRepository: LabelRepositoryProtocol,
        relationRepository: TaskRelationRepositoryProtocol,
        commentRepository: TaskCommentRepositoryProtocol,
        attachmentRepository: TaskAttachmentRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
        quickAddContext: QuickAddContextTracking? = nil,
    ) {
        self.task = task
        self.project = project
        self.repository = repository
        self.labelRepository = labelRepository
        self.relationRepository = relationRepository
        self.commentRepository = commentRepository
        self.attachmentRepository = attachmentRepository
        self.projectRepository = projectRepository
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
        self.quickAddContext = quickAddContext
    }

    /// Call from the view's `onAppear`/`onDisappear`: while this task is the
    /// visible screen, a quick-add from the tab-bar FAB defaults to the
    /// task's project instead of the account default.
    public func markVisible() {
        quickAddContext?.enterProjectScope(project.id)
    }

    public func markHidden() {
        quickAddContext?.exitProjectScope(project.id)
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            task = try await repository.fetchTask(id: task.id)
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Flips the task's completion state, persists the change, and rolls the
    /// local flip back if the server rejects it — mirrors
    /// `ProjectOverviewViewModel.toggleDone(_:)`.
    public func toggleDone() async {
        let previous = task
        task.isDone.toggle()
        if task.isDone {
            hapticPresenter.play(.success)
        }
        await persist(previous: previous)
    }

    /// Sets (or clears, via `nil`) the due date and persists it, rolling back
    /// on failure the same way `toggleDone()` does.
    public func setDueDate(_ dueDate: Date?) async {
        let previous = task
        task.dueDate = dueDate
        await persist(previous: previous)
    }

    /// Sets the priority and persists it, rolling back on failure the same
    /// way `toggleDone()` does.
    public func setPriority(_ priority: VikunjaTask.Priority) async {
        let previous = task
        task.priority = priority
        await persist(previous: previous)
    }

    /// Sets the title and persists it, rolling back on failure the same way
    /// `toggleDone()` does.
    public func setTitle(_ title: String) async {
        let previous = task
        task.title = title
        await persist(previous: previous)
    }

    /// Sets (or clears, via `nil`) the description and persists it, rolling
    /// back on failure the same way `toggleDone()` does.
    public func setDescription(_ description: String?) async {
        let previous = task
        task.description = description
        await persist(previous: previous)
    }

    /// Loads every label on the instance, for the label picker sheet. Failures
    /// leave `allLabels` at whatever it already was (empty on first failure),
    /// rather than surfacing an error — the sheet just shows fewer/no
    /// suggestions to pick from.
    public func loadAllLabels() async {
        allLabels = await (try? labelRepository.fetchLabels()) ?? allLabels
    }

    /// Adds or removes `label` from the task, optimistically, rolling back if
    /// the server rejects it — mirrors `toggleDone()`.
    public func toggleLabel(_ label: Label) async {
        let previous = task
        if task.labels.contains(label) {
            task.labels.removeAll { $0.id == label.id }
            do {
                try await labelRepository.removeLabel(label.id, fromTask: task.id)
            } catch {
                task = previous
            }
        } else {
            task.labels.append(label)
            do {
                try await labelRepository.addLabel(label.id, toTask: task.id)
            } catch {
                task = previous
            }
        }
    }

    /// Creates a new label on the instance and attaches it to the task.
    /// Rolls back to no-op if either the create or the attach request fails —
    /// there's no partial state to reconcile since `allLabels` is reloaded
    /// from the create response rather than guessed at.
    public func createAndAddLabel(title: String, hexColor: String) async {
        guard let created = try? await labelRepository.create(Label(id: 0, title: title, hexColor: hexColor)) else {
            return
        }
        allLabels.append(created)
        await toggleLabel(created)
    }

    /// Adds `relation` under `kind` to the task, optimistically, rolling back
    /// if the server rejects it — mirrors `toggleLabel(_:)`. `relation`'s
    /// display fields (title/isDone/projectID) come from wherever the caller
    /// found the other task (e.g. a search/picker), since Vikunja's
    /// create-relation response only echoes ids, not those fields.
    public func addRelation(_ relation: TaskRelation, kind: RelationKind) async {
        let previous = task
        insertRelation(relation, kind: kind)
        do {
            try await relationRepository.addRelation(kind: kind, otherTaskID: relation.id, toTask: task.id)
            toastPresenter.show("Relation added", style: .success)
        } catch {
            task = previous
        }
    }

    /// Removes `relation` under `kind` from the task, optimistically, rolling
    /// back if the server rejects it — mirrors `toggleLabel(_:)`.
    public func removeRelation(_ relation: TaskRelation, kind: RelationKind) async {
        let previous = task
        deleteRelation(relation, kind: kind)
        do {
            try await relationRepository.removeRelation(kind: kind, otherTaskID: relation.id, fromTask: task.id)
        } catch {
            task = previous
        }
    }

    /// Searches every task the account can see for the "add relation" task
    /// picker, excluding the task itself and anything already related to it
    /// (under any relation kind) so the same task can't be picked twice. An
    /// empty or all-whitespace query falls back to `loadRelationSuggestions()`
    /// rather than clearing the results, so the picker never shows a blank
    /// list just because the user cleared their search. Failures leave
    /// `relationSearchResults` empty rather than surfacing an error — the
    /// sheet just shows no candidates.
    public func searchTasksForRelation(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await loadRelationSuggestions()
            return
        }
        let excludedIDs = relatedTaskIDs.union([task.id])
        let results = await (try? repository.searchTasks(query: query)) ?? []
        relationSearchResults = results.filter { !excludedIDs.contains($0.id) }
    }

    /// Populates `relationSearchResults` with this task's own project's other
    /// tasks before the user has typed anything — most relations (subtasks,
    /// dependencies, blockers) are within the same project, so this saves a
    /// search for the common case. Excludes the task itself and anything
    /// already related to it, the same as `searchTasksForRelation(query:)`.
    public func loadRelationSuggestions() async {
        let excludedIDs = relatedTaskIDs.union([task.id])
        let results = await (try? repository.fetchTasks(projectID: project.id)) ?? []
        relationSearchResults = results.filter { !excludedIDs.contains($0.id) }
    }

    /// Loads every project on the instance, for the "add relation" task
    /// picker to show which project each candidate belongs to. Failures
    /// leave `allProjects` at whatever it already was — the picker just
    /// shows fewer project names, the same tradeoff `loadAllLabels()` makes.
    public func loadAllProjects() async {
        allProjects = await (try? projectRepository.fetchProjects()) ?? allProjects
    }

    /// Moves the task to `project` and persists it, mirroring `persist(previous:)`'s
    /// optimistic-with-rollback pattern. `project` is fixed for this view
    /// model's whole lifetime, so a moved task's own detail screen can no
    /// longer represent it correctly afterwards — the view is expected to
    /// pop back once this returns `true`, the same way it would after
    /// `deleteTask()`.
    public func move(to newProject: Project) async -> Bool {
        let previous = task
        task.projectID = newProject.id
        do {
            var updated = try await repository.update(task)
            updated.subtasks = previous.subtasks
            updated.dependsOn = previous.dependsOn
            updated.blocks = previous.blocks
            updated.otherRelations = previous.otherRelations
            task = updated
            toastPresenter.show("Task moved to \(newProject.title)", style: .success)
            return true
        } catch let error as VikunjaError {
            task = previous
            toastPresenter.show(error.displayMessage, style: .error)
            return false
        } catch {
            task = previous
            toastPresenter.show(error.localizedDescription, style: .error)
            return false
        }
    }

    /// Deletes the task from the server. There's nothing left to show on this
    /// screen once it succeeds — the view is expected to pop back.
    public func deleteTask() async -> Bool {
        do {
            try await repository.delete(id: task.id)
            toastPresenter.show("Task deleted", style: .success)
            return true
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
            return false
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
            return false
        }
    }

    /// Resolves `relation` to the full task and its project, for navigating
    /// to that task's own detail screen when a relation row is tapped —
    /// `TaskRelation` only carries an id/title/isDone/projectID summary, not
    /// enough to push a `TaskDetailView`. Loads `allProjects` first if it
    /// hasn't been already, mirroring the "add relation" picker's lazy load.
    /// Returns `nil` if either fetch fails, or the project can't be resolved.
    public func loadRelatedTask(_ relation: TaskRelation) async -> (VikunjaTask, Project)? {
        guard let relatedTask = try? await repository.fetchTask(id: relation.id) else { return nil }
        if relation.projectID == project.id {
            return (relatedTask, project)
        }
        if allProjects.isEmpty {
            await loadAllProjects()
        }
        guard let relatedProject = allProjects.first(where: { $0.id == relation.projectID }) else { return nil }
        return (relatedTask, relatedProject)
    }

    /// Builds a `TaskDetailViewModel` for a related task, reusing this
    /// view model's own dependencies — lets `TaskDetailView` push another
    /// instance of itself for a tapped relation without the app target's
    /// `AppContainer` needing to know about the recursion.
    public func makeDetailViewModel(task: VikunjaTask, project: Project) -> TaskDetailViewModel {
        TaskDetailViewModel(
            task: task,
            project: project,
            repository: repository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            commentRepository: commentRepository,
            attachmentRepository: attachmentRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            quickAddContext: quickAddContext,
        )
    }

    /// Builds a `DuplicateTaskViewModel` for the current task, reusing this
    /// view model's own repositories — lets `TaskDetailView` present the
    /// duplicate sheet without the app target's `AppContainer` needing a
    /// factory for it (same pattern as `makeDetailViewModel(task:project:)`).
    /// `task` is whatever `load()` last refreshed, so its labels and
    /// relations are current.
    public func makeDuplicateTaskViewModel() -> DuplicateTaskViewModel {
        DuplicateTaskViewModel(
            source: task,
            sourceProject: project,
            taskRepository: repository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )
    }

    /// Loads this task's comments. Failures surface into `commentsLoadState`
    /// (mirroring `load()`) rather than being swallowed like `allLabels`'s
    /// lazy load — comments are always-visible content on this screen, not a
    /// picker's suggestions, so a failure here is worth showing.
    public func loadComments() async {
        if commentsLoadState != .loaded {
            commentsLoadState = .loading
        }
        do {
            comments = try await commentRepository.fetchComments(taskID: task.id)
            commentsLoadState = .loaded
        } catch let error as VikunjaError {
            commentsLoadState = .failure(error.displayMessage)
        } catch {
            commentsLoadState = .failure(error.localizedDescription)
        }
    }

    /// Loads this task's attachments. Failures surface into
    /// `attachmentsLoadState`, the same as `loadComments()`.
    public func loadAttachments() async {
        if attachmentsLoadState != .loaded {
            attachmentsLoadState = .loading
        }
        do {
            attachments = try await attachmentRepository.fetchAttachments(taskID: task.id)
            attachmentsLoadState = .loaded
        } catch let error as VikunjaError {
            attachmentsLoadState = .failure(error.displayMessage)
        } catch {
            attachmentsLoadState = .failure(error.localizedDescription)
        }
    }

    /// Reads the file the user picked through `.fileImporter` off disk and
    /// uploads it. Owning the URL-to-bytes step here (rather than in the view)
    /// keeps the view passive — a read failure surfaces the same toast as any
    /// other unreadable pick, and the upload never starts.
    public func attachFile(at url: URL) async {
        guard let picked = PickedFile(contentsOf: url) else {
            reportAttachmentReadFailure()
            return
        }
        await uploadAttachment(data: picked.data, fileName: picked.fileName, mimeType: picked.mimeType)
    }

    /// Uploads one file and appends the server's created attachment(s) to
    /// `attachments` (their real id/size/uploader only exist once stored, so
    /// there's no optimistic placeholder — same reasoning as `addComment(_:)`).
    /// Surfaces a toast either way.
    public func uploadAttachment(data: Data, fileName: String, mimeType: String) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            let created = try await attachmentRepository.uploadAttachment(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                toTask: task.id,
            )
            attachments.append(contentsOf: created)
            toastPresenter.show("Attachment added", style: .success)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    /// Downloads an attachment's bytes for preview or sharing. Returns `nil`
    /// and surfaces a toast on failure — the caller shows nothing rather than
    /// a broken preview.
    public func attachmentData(for attachment: TaskAttachment) async -> Data? {
        do {
            return try await attachmentRepository.downloadAttachment(
                attachment.id,
                fromTask: task.id,
                previewSize: nil,
            )
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
            return nil
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
            return nil
        }
    }

    /// Downloads an attachment's bytes and stages them to a temp file for
    /// QuickLook, returning the file URL the view presents. The bearer-authed
    /// download can't be handed to QuickLook as a remote URL, so the bytes and
    /// the disk write both belong here, not in the view. Returns `nil` (and the
    /// download surfaces its own toast) if either step fails.
    public func attachmentPreviewURL(for attachment: TaskAttachment) async -> URL? {
        guard let data = await attachmentData(for: attachment) else { return nil }
        return AttachmentPreviewFile.write(data, named: attachment.fileName)
    }

    /// Deletes `attachment`, optimistically removing it and restoring the
    /// whole list if the server rejects it — mirrors `deleteComment(_:)`.
    public func deleteAttachment(_ attachment: TaskAttachment) async {
        let previous = attachments
        attachments.removeAll { $0.id == attachment.id }
        do {
            try await attachmentRepository.deleteAttachment(attachment.id, fromTask: task.id)
            toastPresenter.show("Attachment deleted", style: .success)
        } catch {
            attachments = previous
            toastPresenter.show("Couldn't delete attachment", style: .error)
        }
    }

    /// Surfaces a toast when the file the user picked can't be read off disk
    /// (a security-scoped resource that won't open, an unreadable path) —
    /// the upload never starts in that case.
    public func reportAttachmentReadFailure() {
        toastPresenter.show("Couldn't read that file", style: .error)
    }

    /// Posts a new comment and appends the server's response (its real id,
    /// author, and timestamps) to `comments`. No optimistic append — unlike
    /// `toggleDone()`/`toggleLabel(_:)`, there's no local placeholder worth
    /// showing before the server assigns those fields.
    public func addComment(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let created = try await commentRepository.addComment(trimmed, toTask: task.id)
            comments.append(created)
        } catch {
            toastPresenter.show("Couldn't post comment", style: .error)
        }
    }

    /// Replaces `comment`'s body with `newText`, restoring the whole list if
    /// the server rejects the update — mirrors `deleteComment(_:)`. Unlike a
    /// toggle there's no local placeholder worth showing first: the server
    /// assigns the new `updated` timestamp, so `comments` is only touched once
    /// its response is back (same reasoning as `addComment(_:)`). No-ops on
    /// blank text or an unknown comment id.
    public func editComment(_ comment: TaskComment, newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        do {
            comments[index] = try await commentRepository.updateComment(comment.id, text: trimmed, onTask: task.id)
        } catch {
            toastPresenter.show("Couldn't update comment", style: .error)
        }
    }

    /// Deletes `comment` from the task, optimistically removing it from
    /// `comments` and restoring the whole list if the server rejects the
    /// delete — mirrors `removeRelation(_:kind:)`. No author check: whether
    /// the current user is allowed to delete this comment is the server's
    /// call, and a rejection just rolls back with a toast.
    public func deleteComment(_ comment: TaskComment) async {
        let previous = comments
        comments.removeAll { $0.id == comment.id }
        do {
            try await commentRepository.deleteComment(comment.id, fromTask: task.id)
        } catch {
            comments = previous
            toastPresenter.show("Couldn't delete comment", style: .error)
        }
    }

    /// Resolves `id` to a project title — the current task's own project
    /// (always known, no network needed) or, once `loadAllProjects()` has
    /// run, any other project on the instance. Returns `nil` if `id` isn't
    /// the current project and hasn't been loaded into `allProjects` yet.
    public func projectTitle(forProjectID id: Int) -> String? {
        if id == project.id {
            return project.title
        }
        return allProjects.first { $0.id == id }?.title
    }

    /// Every task id already related to this one, across `subtasks`,
    /// `dependsOn`, `blocks`, and every kind in `otherRelations` — used to
    /// exclude already-related tasks from the relation search results.
    private var relatedTaskIDs: Set<Int> {
        var ids = Set((task.subtasks + task.dependsOn + task.blocks).map(\.id))
        for relations in task.otherRelations.values {
            ids.formUnion(relations.map(\.id))
        }
        return ids
    }

    /// Routes `relation` into whichever of `task`'s relation properties
    /// `kind` corresponds to — the named `subtasks`/`dependsOn`/`blocks`
    /// fields for those three kinds, `otherRelations` for everything else.
    private func insertRelation(_ relation: TaskRelation, kind: RelationKind) {
        switch kind {
        case .subtask: task.subtasks.append(relation)
        case .blocked: task.dependsOn.append(relation)
        case .blocking: task.blocks.append(relation)
        default: task.otherRelations[kind, default: []].append(relation)
        }
    }

    private func deleteRelation(_ relation: TaskRelation, kind: RelationKind) {
        switch kind {
        case .subtask: task.subtasks.removeAll { $0.id == relation.id }
        case .blocked: task.dependsOn.removeAll { $0.id == relation.id }
        case .blocking: task.blocks.removeAll { $0.id == relation.id }
        default:
            task.otherRelations[kind]?.removeAll { $0.id == relation.id }
            if task.otherRelations[kind]?.isEmpty == true {
                task.otherRelations[kind] = nil
            }
        }
    }

    /// Persists the currently-staged `task` edit, rolling back to `previous`
    /// if the server rejects it.
    ///
    /// Vikunja manages relations through their own endpoint rather than the
    /// task update body (see `TaskDTO.relatedTasks`), so `update(_:)`'s
    /// response doesn't carry `subtasks`/`dependsOn`/`blocks`/`otherRelations`
    /// back — carrying over what's already loaded instead of taking the
    /// response as-is is what keeps those sections from disappearing after an
    /// edit.
    private func persist(previous: VikunjaTask) async {
        do {
            var updated = try await repository.update(task)
            updated.subtasks = previous.subtasks
            updated.dependsOn = previous.dependsOn
            updated.blocks = previous.blocks
            updated.otherRelations = previous.otherRelations
            task = updated
        } catch {
            task = previous
        }
    }
}
