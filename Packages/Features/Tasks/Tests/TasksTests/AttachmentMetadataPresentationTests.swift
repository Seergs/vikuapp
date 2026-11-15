import Foundation
@testable import Tasks
import Testing
import VikunjaCore
import VikuUI

private actor AttachmentFetchPause {
    private var paused: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation {
            paused = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilPaused() async {
        if paused != nil {
            return
        }
        await withCheckedContinuation { started = $0 }
    }

    func resume() {
        paused?.resume()
        paused = nil
    }
}

private struct AttachmentOfflineSync: SyncTriggering {
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {
        throw VikunjaError.offline
    }
}

@MainActor
struct AttachmentMetadataPresentationTests {
    private func attachment(_ id: Int = 1) -> TaskAttachment {
        TaskAttachment(
            id: id, taskID: 1, fileName: "spec.pdf", mimeType: "application/pdf", sizeBytes: 2048,
            created: Date(timeIntervalSince1970: 100), createdBy: User(id: 7, username: "sam"),
        )
    }

    private func viewModel(
        repository: FakeTaskAttachmentRepository, toast: FakeToastPresenter = FakeToastPresenter(),
        task: VikunjaTask = VikunjaTask(id: 1, title: "Task", projectID: 1),
        syncTrigger: any SyncTriggering = TestScreenSync(),
    ) -> TaskDetailViewModel {
        TaskDetailViewModel(
            syncTrigger: syncTrigger, localData: TestScreenSync(), task: task,
            project: Project(id: 1, title: "Work"), repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(), attachmentRepository: repository,
            projectRepository: FakeProjectRepository(), toastPresenter: toast,
        )
    }

    @Test(arguments: [false, true])
    func `saved catalogs appear before the network returns without entering loading`(empty: Bool) async {
        let repository = FakeTaskAttachmentRepository()
        let saved = empty ? [] : [attachment()]
        repository.cachedSnapshot = TaskAttachmentSnapshot(attachments: saved, lastSuccessfulDownloadAt: Date())
        repository.attachments = [attachment(2)]
        let vm = viewModel(repository: repository)
        repository.onFetch = { @MainActor in
            #expect(vm.attachments == saved)
            #expect(vm.attachmentsLoadState == .loaded)
            #expect(vm.isRefreshingAttachments)
            #expect(vm.attachmentsNotice == nil)
        }
        await vm.loadAttachments()
        #expect(vm.attachments == [attachment(2)])
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(!vm.isRefreshingAttachments)
        #expect(repository.downloadedPreviewSizes.isEmpty)
    }

    @Test
    func `first visit stays unknown while downloading and confirms empty only after success`() async {
        let repository = FakeTaskAttachmentRepository()
        let vm = viewModel(repository: repository)
        repository.onFetch = { @MainActor in
            #expect(vm.attachmentsLoadState == .loading)
            #expect(vm.isRefreshingAttachments)
        }
        await vm.loadAttachments()
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentsNotice == nil)
    }

    @Test(arguments: [false, true])
    func `failed background updates retain saved information with a quiet retryable notice`(empty: Bool) async {
        let repository = FakeTaskAttachmentRepository()
        let saved = empty ? [] : [attachment()]
        repository.cachedSnapshot = TaskAttachmentSnapshot(attachments: saved, lastSuccessfulDownloadAt: Date())
        repository.fetchError = VikunjaError.offline
        let toast = FakeToastPresenter()
        let vm = viewModel(repository: repository, toast: toast)
        await vm.loadAttachments()
        #expect(vm.attachments == saved)
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(vm.attachmentsRefreshFailed)
        #expect(vm.attachmentsNotice == "You're offline. Connect to update attachments or open files.")
        #expect(toast.shownMessages.isEmpty)

        repository.fetchError = nil
        repository.attachments = [attachment(2)]
        await vm.loadAttachments()
        #expect(vm.attachments == [attachment(2)])
        #expect(!vm.attachmentsRefreshFailed)
        #expect(vm.attachmentsNotice == nil)
    }

    @Test
    func `cancelled background updates keep cached rows without an error notice`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.cachedSnapshot = TaskAttachmentSnapshot(
            attachments: [attachment()], lastSuccessfulDownloadAt: Date(),
        )
        repository.fetchError = CancellationError()
        let vm = viewModel(repository: repository)
        await vm.loadAttachments()
        #expect(vm.attachments == [attachment()])
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(!vm.isRefreshingAttachments)
        #expect(!vm.attachmentsRefreshFailed)
        #expect(vm.attachmentsNotice == nil)
    }

    @Test
    func `cache read failures still allow a server download`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.cacheError = VikunjaError.network("Unreadable cache")
        repository.attachments = [attachment()]
        let vm = viewModel(repository: repository)
        await vm.loadAttachments()
        #expect(vm.attachments == [attachment()])
        #expect(vm.attachmentsLoadState == .loaded)
    }

    @Test
    func `uploaded metadata without complete coverage can still appear immediately`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.cachedSnapshot = TaskAttachmentSnapshot(attachments: [attachment()], lastSuccessfulDownloadAt: nil)
        let vm = viewModel(repository: repository)
        repository.onFetch = { @MainActor in
            #expect(vm.attachments == [attachment()])
            #expect(vm.attachmentsLoadState == .loaded)
        }
        await vm.loadAttachments()
    }

    @Test
    func `local tasks have no remote catalog request or loading state`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.onFetch = { Issue.record("Local tasks must not download attachments") }
        let vm = viewModel(
            repository: repository, task: VikunjaTask(id: .local(UUID()), title: "Task", projectID: 1),
        )
        await vm.loadAttachments()
        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(vm.attachmentsNotice == nil)
    }

    @Test(arguments: [false, true])
    func `late background responses cannot undo uploads or optimistic deletion`(delete: Bool) async {
        let repository = FakeTaskAttachmentRepository()
        repository.cachedSnapshot = TaskAttachmentSnapshot(
            attachments: [attachment()], lastSuccessfulDownloadAt: Date(),
        )
        repository.attachments = [attachment()]
        let pause = AttachmentFetchPause()
        repository.onFetch = { await pause.pause() }
        let vm = viewModel(repository: repository)
        let read = Task { await vm.loadAttachments() }
        await pause.waitUntilPaused()
        if delete {
            await vm.deleteAttachment(attachment())
        } else {
            await vm.uploadAttachment(data: Data(), fileName: "new.txt", mimeType: "text/plain")
        }
        await pause.resume()
        await read.value
        #expect(vm.attachments.map(\.id) == (delete ? [] : [1, 100]))
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(!vm.isRefreshingAttachments)
        #expect(vm.attachmentsNotice == nil)
    }

    @Test(arguments: [false, true])
    func `retry clears attachment offline state even when comment sync previously failed`(cached: Bool) async {
        let repository = FakeTaskAttachmentRepository()
        if cached {
            repository.cachedSnapshot = TaskAttachmentSnapshot(
                attachments: [attachment()], lastSuccessfulDownloadAt: Date(),
            )
        }
        repository.fetchError = VikunjaError.offline
        let vm = viewModel(repository: repository, syncTrigger: AttachmentOfflineSync())
        await vm.start()
        await vm.loadAttachments()
        if cached {
            #expect(vm.attachmentsNotice != nil)
        } else {
            #expect(vm.attachmentsLoadState.failureMessage == "Connect to download this task's attachment list.")
            #expect(vm.attachmentsNotice == nil)
        }
        repository.fetchError = nil
        repository.attachments = [attachment(2)]
        repository.onFetch = { @MainActor in
            #expect(vm.isRetryingAttachments)
            #expect(vm.isRefreshingAttachments)
            #expect(vm.attachmentsNotice == nil)
        }
        await vm.retryAttachmentsDownload()
        #expect(vm.attachments == [attachment(2)])
        #expect(vm.attachmentsLoadState == .loaded)
        #expect(vm.attachmentsNotice == nil)
        #expect(!vm.isRetryingAttachments)
        #expect(!vm.isRefreshingAttachments)
    }

    @Test
    func `a successful attachment request does not inherit an offline comment notice`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.attachments = [attachment()]
        let vm = viewModel(repository: repository, syncTrigger: AttachmentOfflineSync())
        await vm.start()
        await vm.loadAttachments()
        #expect(vm.attachmentsNotice == nil)
        #expect(vm.attachmentsLoadState == .loaded)
    }

    @Test
    func `opening a file provides immediate state and ignores duplicate taps until completion`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.downloadData = [1: Data("PDF".utf8)]
        let pause = AttachmentFetchPause()
        repository.onDownload = { await pause.pause() }
        let vm = viewModel(repository: repository)
        let download = Task { await vm.attachmentData(for: attachment()) }
        await pause.waitUntilPaused()
        #expect(vm.openingAttachmentID == 1)
        #expect(await vm.attachmentData(for: attachment()) == nil)
        #expect(repository.downloadedPreviewSizes.count == 1)
        await pause.resume()
        #expect(await download.value == Data("PDF".utf8))
        #expect(vm.openingAttachmentID == nil)
    }

    @Test
    func `offline file errors explain that opening needs connection without changing the catalog state`() async {
        let repository = FakeTaskAttachmentRepository()
        repository.downloadError = .offline
        let toast = FakeToastPresenter()
        let vm = viewModel(repository: repository, toast: toast)
        #expect(await vm.attachmentData(for: attachment()) == nil)
        #expect(vm.openingAttachmentID == nil)
        #expect(toast.shownMessages.last?.message == "Connect to open this file.")
        #expect(vm.attachmentsNotice == nil)
    }

    @Test
    func `a cancelled file opening clears feedback without presenting data or an error`() async {
        let repository = FakeTaskAttachmentRepository()
        let pause = AttachmentFetchPause()
        repository.onDownload = { await pause.pause() }
        let toast = FakeToastPresenter()
        let vm = viewModel(repository: repository, toast: toast)
        let download = Task { await vm.attachmentData(for: attachment()) }
        await pause.waitUntilPaused()
        download.cancel()
        await pause.resume()
        #expect(await download.value == nil)
        #expect(vm.openingAttachmentID == nil)
        #expect(toast.shownMessages.isEmpty)
    }
}
