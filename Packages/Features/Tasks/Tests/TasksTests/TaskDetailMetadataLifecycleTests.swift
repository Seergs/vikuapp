import Foundation
@testable import Tasks
import Testing
import VikunjaCore
import VikuUI

private enum MetadataReadOutcome: CaseIterable, Sendable {
    case success
    case cancellation
    case failure
}

@MainActor
struct TaskDetailMetadataLifecycleTests {
    private static let calendar = Calendar.current
    private static let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

    @Test(arguments: [false, true], MetadataReadOutcome.allCases)
    private func `seed metadata stays available during delayed and interrupted reads`(
        hadLoaded: Bool, outcome: MetadataReadOutcome,
    ) async {
        let label = Label(id: 3, title: "Navigation", hexColor: "4986A2")
        let task = VikunjaTask(
            id: 1, title: "Plan today", dueDate: Self.noon, priority: .high, projectID: 1, labels: [label],
        )
        let repository = FakeTaskRepository()
        repository.tasks = [task]
        let model = TaskDetailViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(), task: task,
            project: Project(id: 1, title: "Work"), repository: repository,
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(), attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(), toastPresenter: FakeToastPresenter(),
        )
        #expect(model.task == task)
        if hadLoaded {
            await model.load()
        }
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        repository.beforeFetchTaskReturns = {
            entered.continuation.yield(())
            for await _ in release.stream {
                break
            }
            if outcome == .failure {
                throw VikunjaError.offline
            }
        }
        let pending = Task { await model.load() }
        for await _ in entered.stream {
            break
        }

        // These are the fields the view can render while its local read is suspended.
        #expect(model.task == task)
        #expect(model.loadState == (hadLoaded ? .loaded : .loading))
        if outcome == .cancellation {
            pending.cancel()
        }
        release.continuation.yield(())
        await pending.value
        entered.continuation.finish()
        release.continuation.finish()

        #expect(model.task == task)
        switch outcome {
        case .success:
            #expect(model.loadState == .loaded)
        case .cancellation:
            #expect(model.loadState == (hadLoaded ? .loaded : .idle))
        case .failure:
            #expect(model.loadState == (hadLoaded ? .loaded : .failure(VikunjaError.offline.displayMessage)))
        }
    }
}
