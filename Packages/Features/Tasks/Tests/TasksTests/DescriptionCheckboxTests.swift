import Foundation
@testable import Tasks
import Testing
import VikuDesignSystem
import VikunjaCore

@MainActor
struct DescriptionCheckboxTests {
    private let html = #"<ul data-type="taskList"><li data-type="taskItem" data-checked="false"><p>Pack</p></li></ul>"#

    @Test
    func `checkbox changes persist and can be undone with a second tap`() async throws {
        let repository = FakeTaskRepository()
        let viewModel = makeViewModel(repository: repository)
        let index = try checkboxIndex()
        await viewModel.toggleDescriptionCheckbox(at: index, in: html)
        let checked = html.replacingOccurrences(of: "false", with: "true")
        #expect(viewModel.task.description == checked)
        #expect(repository.updatedTasks.last?.description == checked)
        #expect(!viewModel.task.isDone)

        await viewModel.toggleDescriptionCheckbox(at: index, in: checked)
        #expect(viewModel.task.description == html)
        #expect(repository.updatedTasks.count == 2)
        #expect(repository.updatedTasks.last?.description == html)
        #expect(!viewModel.isUpdatingDescriptionCheckbox)
    }

    @Test
    func `failed local save restores the description and reports the error`() async throws {
        let repository = FakeTaskRepository()
        repository.updateError = .network("Failed save")
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(repository: repository, toast: toast)
        try await viewModel.toggleDescriptionCheckbox(at: checkboxIndex(), in: html)
        #expect(viewModel.task.description == html)
        #expect(!viewModel.isUpdatingDescriptionCheckbox)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.first?.style == .error)
    }

    @Test
    func `stale rendered document and invalid reference never save`() async throws {
        let repository = FakeTaskRepository()
        let viewModel = makeViewModel(repository: repository)
        try await viewModel.toggleDescriptionCheckbox(at: checkboxIndex(), in: html + "<p>Stale</p>")
        await viewModel.toggleDescriptionCheckbox(at: -1, in: html)
        #expect(repository.updatedTasks.isEmpty)
        #expect(viewModel.task.description == html)
    }

    @Test(arguments: [false, true])
    func `slow save updates immediately and prevents overlapping checkbox writes`(fails: Bool) async throws {
        let repository = FakeTaskRepository()
        repository.updateError = fails ? .network("Failed save") : nil
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        repository.beforeUpdateReturns = {
            started.continuation.yield(())
            for await _ in release.stream {
                break
            }
        }
        let viewModel = makeViewModel(repository: repository)
        let index = try checkboxIndex()
        let pending = Task { await viewModel.toggleDescriptionCheckbox(at: index, in: html) }
        for await _ in started.stream {
            break
        }
        let checked = html.replacingOccurrences(of: "false", with: "true")
        #expect(viewModel.task.description == checked)
        #expect(viewModel.isUpdatingDescriptionCheckbox)
        await viewModel.toggleDescriptionCheckbox(at: index, in: checked)
        #expect(repository.updatedTasks.count == 1)
        release.continuation.yield(())
        await pending.value
        started.continuation.finish()
        release.continuation.finish()
        #expect(!viewModel.isUpdatingDescriptionCheckbox)
        #expect(viewModel.task.description == (fails ? html : checked))
    }

    @Test
    func `cancelled save rolls back and enables the control without an error toast`() async throws {
        let repository = FakeTaskRepository()
        let started = AsyncStream<Void>.makeStream()
        repository.beforeUpdateReturns = {
            started.continuation.yield(())
            try await Task.sleep(for: .seconds(60))
        }
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(repository: repository, toast: toast)
        let index = try checkboxIndex()
        let pending = Task { await viewModel.toggleDescriptionCheckbox(at: index, in: html) }
        for await _ in started.stream {
            break
        }
        pending.cancel()
        await pending.value
        started.continuation.finish()
        #expect(viewModel.task.description == html)
        #expect(!viewModel.isUpdatingDescriptionCheckbox)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test
    func `already cancelled intent does not start a write`() async throws {
        let repository = FakeTaskRepository()
        let viewModel = makeViewModel(repository: repository)
        let index = try checkboxIndex()
        let pending = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await viewModel.toggleDescriptionCheckbox(at: index, in: html)
        }
        await pending.value
        #expect(repository.updatedTasks.isEmpty)
        #expect(viewModel.task.description == html)
    }

    private func checkboxIndex() throws -> Int {
        guard case let .taskList(items) = RichText.parse(html).first else {
            throw VikunjaError.notFound
        }
        return try #require(items.first?.sourceTokenIndex)
    }

    private func makeViewModel(
        repository: FakeTaskRepository, toast: FakeToastPresenter = FakeToastPresenter(),
    ) -> TaskDetailViewModel {
        TaskDetailViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            task: VikunjaTask(id: .local(UUID()), title: "Travel", description: html, projectID: 1),
            project: Project(id: 1, title: "Personal"), repository: repository,
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(), attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(), toastPresenter: toast,
        )
    }
}
