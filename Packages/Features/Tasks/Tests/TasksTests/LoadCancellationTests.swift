import Foundation
@testable import Tasks
import Testing
import VikunjaCore
import VikuUI

private typealias ReadHook = @Sendable () async throws -> Void
private enum ReadOutcome: CaseIterable, Sendable {
    case cancellation
    case wrappedFailure
    case lateSuccess
}

private struct ReadScenario: Sendable {
    let hadContent: Bool
    let outcome: ReadOutcome
    static var all: [Self] {
        [false, true].flatMap { hadContent in
            ReadOutcome.allCases.map { Self(hadContent: hadContent, outcome: $0) }
        }
    }
}

private actor SuspendedRead {
    nonisolated let entered = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.continuation.yield(())
        }
    }

    func release() {
        continuation?.resume(); continuation = nil
    }
}

@MainActor private final class CancellationToast: ToastPresenting {
    var messages: [String] = []
    func show(_ message: String, style: ToastStyle) {
        messages.append(message)
    }
}

@MainActor private struct LoadFixture {
    let projects = FakeProjectRepository()
    let tasks = FakeTaskRepository()
    let toast = CancellationToast()
    let load: () async -> Void
    let state: () -> ScreenLoadState<Void>
    let content: () -> [String]
    let setHook: (ReadHook?) -> Void

    init(screen: String = "default") {
        projects.projects = [Project(id: 1, title: "Saved")]
        tasks.tasks = [VikunjaTask(id: 1, title: "Saved", projectID: 1)]
        let model = TaskDetailViewModel(
            syncTrigger: TestScreenSync(),
            localData: TestScreenSync(),
            task: tasks.tasks[0],
            project: projects.projects[0],
            repository: tasks,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: projects,
            toastPresenter: toast,
        )
        self.load = { await model.load() }
        self.state = { model.loadState }
        self.content = { [model.task.title] }
        self.setHook = { [tasks] in tasks.beforeFetchTaskReturns = $0 }
    }
}

@MainActor struct LoadCancellationTests {
    @Test(arguments: ["default"], ReadScenario.all)
    private func `cancelled reads preserve content and can be retried`(
        screen: String, scenario: ReadScenario,
    ) async {
        let hadContent = scenario.hadContent
        let outcome = scenario.outcome
        let fixture = LoadFixture(screen: screen)
        if hadContent {
            await fixture.load()
        }
        let saved = fixture.content()
        fixture.projects.projects = [Project(id: 1, title: "Discarded")]
        fixture.tasks.tasks = [VikunjaTask(id: 1, title: "Discarded", projectID: 1)]
        let gate = SuspendedRead()
        fixture.setHook {
            await gate.wait()
            switch outcome {
            case .cancellation: throw CancellationError()
            case .wrappedFailure: throw VikunjaError.network("cancelled dependency")
            case .lateSuccess: return
            }
        }
        let request = Task { await fixture.load() }
        for await _ in gate.entered.stream {
            break
        }
        if outcome != .cancellation {
            request.cancel()
        }
        fixture.projects.projects = []
        fixture.tasks.tasks = []
        await gate.release()
        await request.value
        #expect(fixture.state() == (hadContent ? .loaded : .idle))
        #expect(fixture.content() == saved)
        #expect(fixture.toast.messages.isEmpty)
        fixture.setHook(nil)
        fixture.projects.projects = [Project(id: 1, title: "Recovered")]
        fixture.tasks.tasks = [VikunjaTask(id: 1, title: "Recovered", projectID: 1)]
        await fixture.load()
        #expect(fixture.state() == .loaded)
        #expect(fixture.content() == ["Recovered"])
    }

    @Test(arguments: ["default"])
    func `a cancelled older load cannot overwrite a newer successful load`(screen: String) async {
        let fixture = LoadFixture(screen: screen)
        let gate = SuspendedRead()
        fixture.setHook { await gate.wait(); throw CancellationError() }
        let old = Task { await fixture.load() }
        for await _ in gate.entered.stream {
            break
        }
        fixture.setHook(nil)
        fixture.projects.projects = [Project(id: 1, title: "Fresh")]
        fixture.tasks.tasks = [VikunjaTask(id: 1, title: "Fresh", projectID: 1)]
        await fixture.load()
        old.cancel()
        await gate.release()
        await old.value
        #expect(fixture.state() == .loaded)
        #expect(fixture.content() == ["Fresh"])
        #expect(fixture.toast.messages.isEmpty)
    }

    @Test(arguments: ["default"])
    func `real read failures still show feedback and keep loaded data`(screen: String) async {
        let fixture = LoadFixture(screen: screen)
        await fixture.load()
        fixture.setHook { throw VikunjaError.offline }
        await fixture.load()
        #expect(fixture.state() == .loaded)
        #expect(fixture.content() == ["Saved"])
        #expect(fixture.toast.messages == [VikunjaError.offline.displayMessage])
    }

    @Test(arguments: ["default"])
    func `an already cancelled caller cannot invalidate an active load`(screen: String) async {
        let fixture = LoadFixture(screen: screen)
        let activeGate = SuspendedRead()
        fixture.setHook { await activeGate.wait() }
        let active = Task { await fixture.load() }
        for await _ in activeGate.entered.stream {
            break
        }
        fixture.setHook(nil)
        let launchGate = SuspendedRead()
        let cancelled = Task {
            await launchGate.wait()
            await fixture.load()
        }
        for await _ in launchGate.entered.stream {
            break
        }
        cancelled.cancel()
        await launchGate.release()
        await cancelled.value
        await activeGate.release()
        await active.value
        #expect(fixture.state() == .loaded)
        #expect(fixture.content() == ["Saved"])
        #expect(fixture.toast.messages.isEmpty)
    }
}
