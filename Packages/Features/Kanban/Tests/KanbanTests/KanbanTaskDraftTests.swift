import Foundation
@testable import Kanban
import Testing
import VikunjaCore

@MainActor
struct KanbanTaskDraftTests {
    @Test(arguments: [false, true])
    func `submission preserves the draft until success and prevents duplicate creation`(succeeds: Bool) async {
        let draft = KanbanTaskDraft()
        draft.isPresented = true
        draft.title = "  New card \n"
        var submissions = 0

        await draft.submit { title in
            submissions += 1
            #expect(title == "New card")
            #expect(draft.isSubmitting)
            #expect(draft.isPresented)
            #expect(draft.title == "  New card \n")
            // A second submission while the first is suspended must not create another task.
            await Task.yield()
            await draft.submit { _ in
                submissions += 1
                return true
            }
            return succeeds
        }

        #expect(submissions == 1)
        #expect(!draft.isSubmitting)
        #expect(draft.isPresented == !succeeds)
        #expect(draft.title == (succeeds ? "" : "  New card \n"))
    }

    @Test func `empty or dismissed drafts do not create tasks`() async {
        let draft = KanbanTaskDraft()
        draft.title = "Unsent draft"
        await draft.submit { _ in Issue.record("Dismissed draft submitted"); return true }
        draft.isPresented = true
        draft.title = " \n "
        await draft.submit { _ in Issue.record("Empty draft submitted"); return true }
        #expect(draft.isPresented)
        #expect(!draft.isSubmitting)
    }

    @Test func `failed or cancelled creation preserves input and can be retried offline`() async {
        let repository = FakeBucketRepository()
        repository.buckets = [KanbanBucket(id: 1, title: "To Do")]
        let toast = FakeToastPresenter()
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"), repository: repository,
            syncTrigger: TestScreenSync(), localData: TestScreenSync(), toastPresenter: toast,
        )
        await viewModel.load()
        let draft = KanbanTaskDraft()
        draft.isPresented = true
        draft.title = "Offline card"
        let bucket = viewModel.buckets[0]

        repository.createError = CancellationError()
        await draft.submit { await viewModel.createTask(title: $0, in: bucket) }
        #expect(draft.isPresented)
        #expect(draft.title == "Offline card")
        #expect(toast.shownMessages.isEmpty)

        repository.createError = VikunjaError.offline
        await draft.submit { await viewModel.createTask(title: $0, in: bucket) }
        #expect(draft.isPresented)
        #expect(draft.title == "Offline card")
        #expect(toast.shownMessages.map(\.style) == [.info])

        // Project boards accept a durable local task without a connection.
        repository.createError = nil
        await draft.submit { await viewModel.createTask(title: $0, in: bucket) }
        #expect(!draft.isPresented)
        #expect(draft.title.isEmpty)
        #expect(repository.createdTasks.count == 1)
        #expect(viewModel.buckets[0].tasks.map(\.title) == ["Offline card"])
    }
}
