import Foundation
@testable import Tasks
import VikunjaCore

final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var fetchError: VikunjaError?
    var createError: VikunjaError?
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    var searchError: VikunjaError?
    var searchResults: [VikunjaTask] = []
    /// Artificial delay before `fetchTask(id:)` returns — lets tests simulate
    /// a slower, earlier-issued `load()` that resolves after a faster edit
    /// issued while it was still in flight.
    var fetchTaskDelay: Duration?
    private var nextID = 1000

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        if let fetchError {
            throw fetchError
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        // Snapshot before the delay, not after — mirrors a real slow request:
        // the response body reflects server state as of when the server
        // processed it, not whatever's changed by the time it reaches the
        // client. Reading `tasks` after the sleep would let a same-second
        // `update(_:)` from a concurrent edit "fix" this response, which
        // isn't how the real race a delayed `fetchTask` is standing in for
        // actually plays out.
        let snapshotError = fetchError
        let snapshotTask = tasks.first(where: { $0.id == id })
        if let fetchTaskDelay {
            try? await Task.sleep(for: fetchTaskDelay)
        }
        if let snapshotError {
            throw snapshotError
        }
        guard let task = snapshotTask else {
            throw VikunjaError.notFound
        }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let createError {
            throw createError
        }
        // Mirrors the real API: the server assigns the id. Relations/labels
        // aren't accepted in the create body, so they're dropped here too.
        let created = VikunjaTask(
            id: nextID,
            title: task.title,
            description: task.description,
            isDone: task.isDone,
            dueDate: task.dueDate,
            priority: task.priority,
            projectID: task.projectID,
        )
        nextID += 1
        tasks.append(created)
        return created
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let updateError {
            throw updateError
        }
        // Mirrors the real API: an update's response doesn't echo relations
        // back (see `TaskDetailViewModel.toggleDone()`'s doc comment).
        var updated = task
        updated.subtasks = []
        updated.dependsOn = []
        updated.blocks = []
        updated.otherRelations = [:]
        return updated
    }

    func delete(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query _: String) async throws -> [VikunjaTask] {
        if let searchError {
            throw searchError
        }
        return searchResults
    }
}

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var fetchError: VikunjaError?

    func fetchProjects() async throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return projects
    }

    func fetchProject(id: Int) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id: Int) async throws {
        projects.removeAll { $0.id == id }
    }
}

@MainActor
final class FakeQuickAddContext: QuickAddContextTracking {
    private(set) var scopes: [Int] = []
    var preselectedProjectID: Int? {
        scopes.last
    }

    func enterProjectScope(_ projectID: Int) {
        scopes.append(projectID)
    }

    func exitProjectScope(_ projectID: Int) {
        if let index = scopes.lastIndex(of: projectID) {
            scopes.remove(at: index)
        }
    }
}

@MainActor
final class FakeTaskChangeBroadcaster: TaskChangeBroadcasting {
    private(set) var lastCreatedTask: TaskCreatedEvent?

    func taskCreated(projectID: Int) {
        lastCreatedTask = TaskCreatedEvent(projectID: projectID)
    }
}

final class FakeLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    var labels: [Label] = []
    var addedLabelIDs: [(labelID: Int, taskID: Int)] = []
    var removedLabelIDs: [(labelID: Int, taskID: Int)] = []
    var fetchError: VikunjaError?
    var createError: VikunjaError?
    var addError: VikunjaError?
    var removeError: VikunjaError?
    private var nextID = 100

    func fetchLabels() async throws -> [Label] {
        if let fetchError {
            throw fetchError
        }
        return labels
    }

    func create(_ label: Label) async throws -> Label {
        if let createError {
            throw createError
        }
        let created = Label(id: nextID, title: label.title, hexColor: label.hexColor)
        nextID += 1
        labels.append(created)
        return created
    }

    func update(_ label: Label) async throws -> Label {
        label
    }

    func delete(id: Int) async throws {
        labels.removeAll { $0.id == id }
    }

    func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        if let addError {
            throw addError
        }
        addedLabelIDs.append((labelID, taskID))
    }

    func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        if let removeError {
            throw removeError
        }
        removedLabelIDs.append((labelID, taskID))
    }
}

final class FakeTaskRelationRepository: TaskRelationRepositoryProtocol, @unchecked Sendable {
    struct RecordedRelation: Sendable {
        let kind: RelationKind
        let otherTaskID: Int
        let taskID: Int
    }

    var addedRelations: [RecordedRelation] = []
    var removedRelations: [RecordedRelation] = []
    var addError: VikunjaError?
    var removeError: VikunjaError?

    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        if let addError {
            throw addError
        }
        addedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }

    func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {
        if let removeError {
            throw removeError
        }
        removedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }
}

final class FakeTaskCommentRepository: TaskCommentRepositoryProtocol, @unchecked Sendable {
    var comments: [TaskComment] = []
    var fetchError: VikunjaError?
    var addError: VikunjaError?
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    /// Artificial delay before `fetchComments(taskID:)` returns — lets tests
    /// simulate a slower, earlier-issued `loadComments()` that resolves after
    /// a faster `addComment(_:)`/`deleteComment(_:)` issued while it was
    /// still in flight.
    var fetchCommentsDelay: Duration?
    private var nextID = 100

    func fetchComments(taskID _: Int) async throws -> [TaskComment] {
        // Snapshot before the delay — see `FakeTaskRepository.fetchTask`'s
        // comment for why.
        let snapshotError = fetchError
        let snapshot = comments
        if let fetchCommentsDelay {
            try? await Task.sleep(for: fetchCommentsDelay)
        }
        if let snapshotError {
            throw snapshotError
        }
        return snapshot
    }

    func addComment(_ text: String, toTask _: Int) async throws -> TaskComment {
        if let addError {
            throw addError
        }
        let created = TaskComment(
            id: nextID,
            comment: text,
            author: User(id: 1, username: "me"),
            created: Date(),
            updated: Date(),
        )
        nextID += 1
        comments.append(created)
        return created
    }

    func updateComment(_ commentID: Int, text: String, onTask _: Int) async throws -> TaskComment {
        if let updateError {
            throw updateError
        }
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else {
            throw VikunjaError.notFound
        }
        comments[index].comment = text
        comments[index].updated = Date()
        return comments[index]
    }

    func deleteComment(_ commentID: Int, fromTask _: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        comments.removeAll { $0.id == commentID }
    }
}

final class FakeTaskAttachmentRepository: TaskAttachmentRepositoryProtocol, @unchecked Sendable {
    var attachments: [TaskAttachment] = []
    var downloadData: [Int: Data] = [:]
    var fetchError: VikunjaError?
    var uploadError: VikunjaError?
    var downloadError: VikunjaError?
    var deleteError: VikunjaError?
    struct RecordedUpload: Sendable {
        let fileName: String
        let mimeType: String
        let size: Int
        let taskID: Int
    }

    private(set) var uploaded: [RecordedUpload] = []
    private(set) var downloadedPreviewSizes: [AttachmentPreviewSize?] = []
    private var nextID = 100

    func fetchAttachments(taskID _: Int) async throws -> [TaskAttachment] {
        if let fetchError {
            throw fetchError
        }
        return attachments
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        if let uploadError {
            throw uploadError
        }
        uploaded.append(RecordedUpload(fileName: fileName, mimeType: mimeType, size: data.count, taskID: taskID))
        let created = TaskAttachment(
            id: nextID,
            taskID: taskID,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: data.count,
            created: Date(),
            createdBy: User(id: 1, username: "me"),
        )
        nextID += 1
        attachments.append(created)
        return [created]
    }

    func downloadAttachment(
        _ id: Int,
        fromTask _: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        downloadedPreviewSizes.append(previewSize)
        if let downloadError {
            throw downloadError
        }
        return downloadData[id] ?? Data()
    }

    func deleteAttachment(_ id: Int, fromTask _: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        attachments.removeAll { $0.id == id }
    }
}

final class FakeToastPresenter: ToastPresenting, @unchecked Sendable {
    private(set) var shownMessages: [(message: String, style: ToastStyle)] = []

    func show(_ message: String, style: ToastStyle) {
        shownMessages.append((message, style))
    }
}

final class FakeHapticPresenter: HapticFeedbackPresenting, @unchecked Sendable {
    private(set) var played: [HapticStyle] = []

    func play(_ style: HapticStyle) {
        played.append(style)
    }
}
