import Foundation
@testable import Tasks
import Testing
import VikunjaCore

private actor CommentSyncTrigger: SyncTriggering {
    var error: VikunjaError?
    private(set) var requestedScopes: [SyncScope] = []
    init(error: VikunjaError? = nil) {
        self.error = error
    }

    func setError(_ error: VikunjaError?) {
        self.error = error
    }

    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {
        requestedScopes.append(scope)
        if let error {
            throw error
        }
    }
}

private struct GatedCommentSync: SyncTriggering {
    let entered: AsyncStream<Void>.Continuation
    let release: AsyncStream<Void>
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {
        entered.yield(())
        for await _ in release {
            break
        }
        try Task.checkCancellation()
    }
}

@MainActor
struct CommentAvailabilityTests {
    private func makeViewModel(
        comments: FakeTaskCommentRepository,
        sync: any SyncTriggering,
    ) -> TaskDetailViewModel {
        let task = VikunjaTask(id: 1, title: "Cached task", projectID: 1)
        let tasks = FakeTaskRepository()
        tasks.tasks = [task]
        return TaskDetailViewModel(
            syncTrigger: sync, localData: TestScreenSync(), task: task,
            project: Project(id: 1, title: "Work"), repository: tasks,
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            commentRepository: comments, attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(), toastPresenter: FakeToastPresenter(),
        )
    }

    @Test func `unsynced local task does not ask to download a nonexistent server conversation`() async {
        let comments = FakeTaskCommentRepository()
        comments.lastSuccessfulDownloadAt = nil
        comments.isLocalOnly = true
        let model = makeViewModel(comments: comments, sync: CommentSyncTrigger(error: .offline))
        await model.start()
        #expect(model.commentsNotice == nil)
        #expect(!model.canRetryCommentsDownload)
    }

    @Test func `never downloaded offline conversation explains missing coverage`() async {
        let comments = FakeTaskCommentRepository()
        comments.lastSuccessfulDownloadAt = nil
        let model = makeViewModel(comments: comments, sync: CommentSyncTrigger(error: .offline))
        await model.start()
        #expect(model.comments.isEmpty)
        #expect(model.commentsNotice == "Connect to download this task's comments.")
        #expect(model.canRetryCommentsDownload)
    }

    @Test func `downloaded empty conversation remains distinguishable offline`() async {
        let comments = FakeTaskCommentRepository()
        let model = makeViewModel(comments: comments, sync: CommentSyncTrigger(error: .offline))
        await model.start()
        #expect(model.comments.isEmpty)
        #expect(model.commentsLastSuccessfulDownloadAt != nil)
        #expect(model.commentsNotice == "You're offline. There may be comments you haven't downloaded yet.")
        #expect(model.canRetryCommentsDownload)
    }

    @Test func `successful empty download allows the no comments placeholder`() async {
        let model = makeViewModel(comments: FakeTaskCommentRepository(), sync: CommentSyncTrigger())
        await model.start()
        #expect(model.comments.isEmpty)
        #expect(model.commentsNotice == nil)
        #expect(!model.canRetryCommentsDownload)
    }

    @Test func `local pending comments remain visible without implying downloaded coverage`() async {
        let comments = FakeTaskCommentRepository()
        comments.lastSuccessfulDownloadAt = nil
        let model = makeViewModel(comments: comments, sync: CommentSyncTrigger(error: .offline))
        await model.start()
        await model.addComment("Written offline")
        #expect(model.comments.map(\.comment) == ["Written offline"])
        #expect(model.commentsLastSuccessfulDownloadAt == nil)
        #expect(model.commentsNotice == "Connect to download this task's comments.")
    }

    @Test func `failed refresh preserves cached comments and offers recovery`() async {
        let comments = FakeTaskCommentRepository()
        comments.comments = [TaskComment(
            id: 1, comment: "Cached", author: User(id: 1, username: "me"), created: Date(), updated: Date(),
        )]
        let model = makeViewModel(comments: comments, sync: CommentSyncTrigger(error: .timeout))
        await model.start()
        #expect(model.comments.map(\.comment) == ["Cached"])
        #expect(model.commentsNotice == "Couldn't update comments. Try again.")
        #expect(model.canRetryCommentsDownload)
    }

    @Test func `reconnecting and retrying replaces the offline notice with confirmed empty state`() async {
        let comments = FakeTaskCommentRepository()
        comments.lastSuccessfulDownloadAt = nil
        let sync = CommentSyncTrigger(error: .offline)
        let model = makeViewModel(comments: comments, sync: sync)
        await model.start()
        #expect(model.commentsNotice != nil)
        await sync.setError(nil)
        comments.lastSuccessfulDownloadAt = Date()
        await model.retryCommentsDownload()
        #expect(await sync.requestedScopes == [.comments(.remote(1)), .comments(.remote(1))])
        #expect(model.attachmentsLoadState == .idle)
        #expect(model.commentsNotice == nil)
        #expect(!model.canRetryCommentsDownload)
    }

    @Test func `slow initial download does not show an empty conversation and cancellation permits retry`() async {
        let comments = FakeTaskCommentRepository()
        comments.lastSuccessfulDownloadAt = nil
        let (entered, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        let model = makeViewModel(comments: comments, sync: GatedCommentSync(entered: signal, release: release))
        let opening = Task { await model.start() }
        var iterator = entered.makeAsyncIterator()
        _ = await iterator.next()
        #expect(model.commentsNotice == "Loading comments…")
        #expect(!model.canRetryCommentsDownload)
        opening.cancel()
        resume.finish()
        await opening.value
        #expect(model.commentsNotice == "This task's comments haven't been downloaded yet.")
        #expect(model.canRetryCommentsDownload)
    }
}
