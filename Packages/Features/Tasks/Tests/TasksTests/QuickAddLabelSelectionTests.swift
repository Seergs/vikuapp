import Foundation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddLabelSelectionTests {
    private let client = Label(id: 10, title: "Client", hexColor: "6449A2")
    private let design = Label(id: 11, title: "Design", hexColor: "196AFF")

    private func makeModel(
        labels: FakeLabelRepository,
        tasks: FakeTaskRepository = FakeTaskRepository(),
        syntax: QuickAddSyntax? = .todoist,
        toast: FakeToastPresenter = FakeToastPresenter(),
    ) -> QuickAddTaskViewModel {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Inbox")]
        return QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: tasks,
            projectRepository: projects,
            toastPresenter: toast,
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            labelRepository: labels,
        )
    }

    @Test(arguments: [QuickAddSyntax?.none, .todoist, .vikunja])
    func `picker selections stay in the draft and attach only when the task is created`(syntax: QuickAddSyntax?) async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let tasks = FakeTaskRepository()
        let model = makeModel(labels: labels, tasks: tasks, syntax: syntax)
        await model.load()
        model.input = "Review report"
        model.toggleLabel(client)
        model.toggleLabel(design)
        #expect(model.selectedLabels == [client, design])
        #expect(model.selectedLabels.first?.title == "Client")
        #expect(model.selectedLabels.count - 1 == 1)
        #expect(labels.addedLabelIDs.isEmpty)
        #expect(tasks.tasks.isEmpty)
        let created = try #require(await model.save())
        #expect(created.title == "Review report")
        #expect(labels.addedLabelIDs.map(\.labelID) == [client.id, design.id])
        #expect(labels.addedLabelIDs.allSatisfy { $0.taskID == created.id })
        #expect(labels.labels == [client, design])
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `typed local labels retain their identity and attach alongside remote labels`(syntax: QuickAddSyntax) async throws {
        let local = Label(id: .local(UUID()), title: "Offline", hexColor: "6449A2")
        let labels = FakeLabelRepository()
        labels.labels = [client, local]
        let model = makeModel(labels: labels, syntax: syntax)
        await model.load()
        model.input = "Review \(syntax.labelSigil)Offline \(syntax.labelSigil)Client"
        #expect(model.selectedLabels == [local, client])
        let created = try #require(await model.save())
        #expect(created.title == "Review")
        #expect(labels.addedLabelIDs.map(\.labelID) == [local.id, client.id])
        #expect(labels.labels.count == 2)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `picker and typed selections merge without duplicates and preserve the first selection`(syntax: QuickAddSyntax) async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let model = makeModel(labels: labels, syntax: syntax)
        await model.load()
        model.input = "Review \(syntax.labelSigil)Client"
        model.toggleLabel(design)
        model.input += " \(syntax.labelSigil)Design \(syntax.labelSigil)Client"
        #expect(model.selectedLabels == [client, design])
        _ = try #require(await model.save())
        #expect(labels.addedLabelIDs.map(\.labelID) == [client.id, design.id])
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `deselecting removes all matching shortcuts without removing other labels or the due date`(syntax: QuickAddSyntax) async throws {
        let labels = FakeLabelRepository()
        let quoted = Label(id: 12, title: "Client team", hexColor: "6449A2")
        labels.labels = [quoted, design]
        let model = makeModel(labels: labels, syntax: syntax)
        await model.load()
        model.input = "📋 Review \(syntax.labelSigil)\"Client team\" \(syntax.labelSigil)Design \(syntax.labelSigil)\"Client team\""
        let date = Date(timeIntervalSince1970: 1_794_574_800)
        model.pickDueDate(date)
        model.toggleLabel(quoted)
        #expect(model.input == "📋 Review \(syntax.labelSigil)Design")
        #expect(model.selectedLabels == [design])
        #expect(model.dueDate == date)
        model.input += " updated"
        #expect(model.selectedLabels == [design])
        let created = try #require(await model.save())
        #expect(created.dueDate == date)
        #expect(labels.addedLabelIDs.map(\.labelID) == [design.id])
    }

    @Test func `removing the first picker selection shows the next one and leaves text untouched`() async {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let model = makeModel(labels: labels, syntax: nil)
        await model.load()
        model.input = "  Review @Client  "
        model.toggleLabel(client)
        model.toggleLabel(design)
        model.toggleLabel(client)
        #expect(model.selectedLabels == [design])
        #expect(model.input == "  Review @Client  ")
        model.toggleLabel(design)
        #expect(model.selectedLabels.isEmpty)
    }

    @Test func `editing typed labels changes selection while independent picker choices remain`() async {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let model = makeModel(labels: labels)
        await model.load()
        model.input = "Review"
        model.toggleLabel(client)
        model.input += " @Design"
        #expect(model.selectedLabels == [client, design])
        model.input = "Review"
        #expect(model.selectedLabels == [client])
    }

    @Test func `catalog refresh reconciles local and remote identities without changing the first selection`() async throws {
        let local = Label(id: .local(UUID()), title: "Client", hexColor: "6449A2")
        let labels = FakeLabelRepository()
        labels.labels = [local, design]
        let model = makeModel(labels: labels)
        await model.load()
        model.input = "Review"
        model.toggleLabel(local)
        model.toggleLabel(design)
        labels.labels = [client, design]
        labels.aliases = [local.id: client.id]
        await model.loadLabels()
        model.input += " @Client"
        #expect(model.selectedLabels == [client, design])
        _ = try #require(await model.save())
        #expect(labels.addedLabelIDs.map(\.labelID) == [client.id, design.id])
        model.toggleLabel(local)
        #expect(model.selectedLabels == [design])
        #expect(model.input == "Review")
    }

    @Test func `labels with identical titles remain distinct by identity`() async throws {
        let other = Label(id: 12, title: "Client", hexColor: "196AFF")
        let labels = FakeLabelRepository()
        labels.labels = [client, other]
        let model = makeModel(labels: labels)
        await model.load()
        model.input = "Review"
        model.toggleLabel(client)
        model.toggleLabel(other)
        #expect(model.selectedLabels == [client, other])
        _ = try #require(await model.save())
        #expect(labels.addedLabelIDs.map(\.labelID) == [client.id, other.id])
    }

    @Test func `label load failure is independent of projects and retry retains the draft selection`() async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client]
        let tasks = FakeTaskRepository()
        let model = makeModel(labels: labels, tasks: tasks)
        await model.load()
        model.input = "Review"
        model.toggleLabel(client)
        labels.fetchError = .network("offline")
        await model.loadLabels()
        #expect(model.loadState == .loaded)
        if case .failure = model.labelsLoadState {} else {
            Issue.record("Expected a retryable label failure")
        }
        #expect(model.selectedLabels == [client])
        #expect(await model.save() == nil)
        #expect(tasks.tasks.isEmpty)
        #expect(model.input == "Review")
        labels.fetchError = nil
        await model.loadLabels()
        #expect(model.labelsLoadState == .loaded)
        let created = try #require(await model.save())
        #expect(created.title == "Review")
        #expect(labels.addedLabelIDs.map(\.labelID) == [client.id])
    }

    @Test func `a failed task creation keeps picker selections for one successful retry`() async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let tasks = FakeTaskRepository()
        let model = makeModel(labels: labels, tasks: tasks)
        await model.load()
        model.input = "Review"
        model.toggleLabel(client)
        model.toggleLabel(design)
        tasks.createError = .network("offline")
        #expect(await model.save() == nil)
        #expect(model.selectedLabels == [client, design])
        #expect(labels.addedLabelIDs.isEmpty)
        tasks.createError = nil
        _ = try #require(await model.save())
        #expect(tasks.tasks.count == 1)
        #expect(labels.addedLabelIDs.map(\.labelID) == [client.id, design.id])
    }

    @Test func `cancelled creation retains selected local labels for retry`() async throws {
        let local = Label(id: .local(UUID()), title: "Client", hexColor: "6449A2")
        let labels = FakeLabelRepository()
        labels.labels = [local]
        let tasks = FakeTaskRepository()
        tasks.beforeCreateReturns = { try Task.checkCancellation() }
        let model = makeModel(labels: labels, tasks: tasks)
        await model.load()
        model.input = "Review"
        model.toggleLabel(local)
        let operation = Task { await model.save() }
        operation.cancel()
        #expect(await operation.value == nil)
        #expect(tasks.tasks.isEmpty)
        #expect(labels.addedLabelIDs.isEmpty)
        #expect(model.selectedLabels == [local])
        tasks.beforeCreateReturns = nil
        _ = try #require(await model.save())
        #expect(labels.addedLabelIDs.map(\.labelID) == [local.id])
    }

    @Test func `an association failure reports the created task instead of inviting a duplicate creation`() async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client]
        labels.addError = .network("offline")
        let tasks = FakeTaskRepository()
        let toast = FakeToastPresenter()
        let model = makeModel(labels: labels, tasks: tasks, toast: toast)
        await model.load()
        model.input = "Review"
        model.toggleLabel(client)
        _ = try #require(await model.save())
        #expect(tasks.tasks.count == 1)
        #expect(toast.shownMessages.last?.style == .error)
        #expect(model.saveErrorMessage == nil)
    }

    @Test func `a typed local label resolves after initial load without creating a duplicate label`() async throws {
        let local = Label(id: .local(UUID()), title: "Client", hexColor: "6449A2")
        let labels = FakeLabelRepository()
        labels.labels = [local]
        let model = makeModel(labels: labels)
        model.input = "Review @Client"
        #expect(model.selectedLabels.isEmpty)
        #expect(await model.save() == nil)
        await model.load()
        #expect(model.selectedLabels == [local])
        _ = try #require(await model.save())
        #expect(labels.labels == [local])
        #expect(labels.addedLabelIDs.map(\.labelID) == [local.id])
    }
}
