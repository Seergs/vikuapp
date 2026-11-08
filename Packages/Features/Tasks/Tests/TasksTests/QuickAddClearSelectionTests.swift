import Foundation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddClearSelectionTests {
    private let client = Label(id: 10, title: "Client", hexColor: "6449A2")
    private let design = Label(id: 11, title: "Design", hexColor: "196AFF")

    private func makeModel(
        syntax: QuickAddSyntax?,
        labels: FakeLabelRepository,
        tasks: FakeTaskRepository = FakeTaskRepository(),
    ) throws -> QuickAddTaskViewModel {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Inbox")]
        let zone = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 12,
        )))
        return QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: tasks,
            projectRepository: projects,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            labelRepository: labels,
            dateParsingContext: .init(referenceDate: reference, timeZone: zone, languages: [.spanish, .english]),
        )
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `clear labels removes picker selections and applied shortcuts including new label intents`(
        syntax: QuickAddSyntax,
    ) async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let model = try makeModel(syntax: syntax, labels: labels)
        await model.load()
        let priority = "\(syntax.priorityPrefix)1"
        model.input = "Review \(syntax.labelSigil)Client \(syntax.labelSigil)New \(syntax.labelSigil)Client \(syntax.projectSigil)Inbox \(priority) tomorrow"
        model.toggleLabel(design)
        let dueDate = try #require(model.dueDate)
        let selectedPriority = model.priority
        #expect(model.selectedLabels.count == 2)
        #expect(!model.parsed.newLabelNames.isEmpty)
        model.clearLabels()
        #expect(model.selectedLabels.isEmpty)
        #expect(model.parsed.newLabelNames.isEmpty)
        #expect(model.input == "Review \(syntax.projectSigil)Inbox \(priority) tomorrow")
        #expect(model.dueDate == dueDate)
        #expect(model.priority == selectedPriority)
        #expect(model.selectedProjectID == 1)
        model.input += " updated"
        #expect(model.selectedLabels.isEmpty)
        let created = try #require(await model.save())
        #expect(created.title == "Review updated")
        #expect(created.dueDate == dueDate)
        #expect(created.priority == selectedPriority)
        #expect(labels.addedLabelIDs.isEmpty)
        #expect(labels.labels == [client, design])
    }

    @Test func `clear labels with magic disabled preserves literal shortcut-like text`() async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client, design]
        let model = try makeModel(syntax: nil, labels: labels)
        await model.load()
        model.input = "Review @Client @Design"
        model.toggleLabel(client)
        model.toggleLabel(design)
        model.clearLabels()
        #expect(model.selectedLabels.isEmpty)
        #expect(model.input == "Review @Client @Design")
        _ = try #require(await model.save())
        #expect(labels.addedLabelIDs.isEmpty)
    }

    @Test func `clear labels remains recoverable after a catalog refresh failure`() async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client]
        let model = try makeModel(syntax: .todoist, labels: labels)
        await model.load()
        model.input = "Review @Client"
        model.toggleLabel(design)
        labels.fetchError = .network("offline")
        await model.loadLabels()
        model.clearLabels()
        #expect(model.input == "Review")
        #expect(model.selectedLabels.isEmpty)
        #expect(model.canSave)
        _ = try #require(await model.save())
        #expect(labels.addedLabelIDs.isEmpty)
        #expect(labels.labels == [client])
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `clear priority removes superseded tokens too and preserves the date and relative reminder`(
        syntax: QuickAddSyntax,
    ) async throws {
        let labels = FakeLabelRepository()
        let model = try makeModel(syntax: syntax, labels: labels)
        await model.load()
        model.input = "Review \(syntax.priorityPrefix)1 \(syntax.priorityPrefix)2 \(syntax.projectSigil)Inbox tomorrow"
        let date = try #require(model.dueDate)
        model.setReminder(TaskReminder(reminder: date, relativePeriod: -3600, relativeTo: .dueDate))
        let reminder = model.reminder
        model.pickPriority(.unset)
        #expect(model.priority == .unset)
        #expect(model.parsed.priority == nil)
        #expect(model.input == "Review \(syntax.projectSigil)Inbox tomorrow")
        #expect(model.dueDate == date)
        #expect(model.reminder == reminder)
        #expect(!model.isConfirmingDueDateRemoval)
        model.input += " updated"
        #expect(model.priority == .unset)
        let created = try #require(await model.save())
        #expect(created.priority == .unset)
        #expect(created.dueDate == date)
        #expect(try created.reminders == [#require(reminder)])
        model.pickPriority(.low)
        #expect(model.priority == .low)
        #expect(model.parsed.priority == .low)
    }

    @Test func `clear priority with magic disabled leaves literal priority text unchanged`() async throws {
        let labels = FakeLabelRepository()
        let model = try makeModel(syntax: nil, labels: labels)
        await model.load()
        model.input = "Review p1 !2"
        model.pickPriority(.high)
        model.pickPriority(.unset)
        #expect(model.input == "Review p1 !2")
        #expect(model.priority == .unset)
        #expect(try #require(await model.save()).priority == .unset)
    }

    @Test func `clearing each chip changes only that field and keeps linked date confirmation`() async throws {
        let labels = FakeLabelRepository()
        labels.labels = [client]
        let model = try makeModel(syntax: nil, labels: labels)
        await model.load()
        model.input = "Review"
        let date = model.dateParsingContext.referenceDate.addingTimeInterval(86400)
        model.pickDueDate(date)
        model.setReminder(TaskReminder(reminder: date, relativePeriod: -1800, relativeTo: .dueDate))
        model.pickPriority(.high)
        model.toggleLabel(client)
        let reminder = model.reminder
        model.clearLabels()
        #expect(model.priority == .high)
        #expect(model.reminder == reminder)
        #expect(model.dueDate == date)
        model.pickPriority(.unset)
        #expect(model.reminder == reminder)
        #expect(model.dueDate == date)
        model.pickDueDate(nil)
        #expect(model.isConfirmingDueDateRemoval)
        #expect(model.dueDate == date)
        #expect(model.reminder == reminder)
        model.cancelDueDateRemoval()
        model.setReminder(nil)
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.dueDate == date)
        model.pickDueDate(nil)
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.selectedProjectID == 1)
        let created = try #require(await model.save())
        #expect(created.dueDate == nil)
        #expect(created.reminders.isEmpty)
        #expect(created.priority == .unset)
        #expect(labels.addedLabelIDs.isEmpty)
    }
}
