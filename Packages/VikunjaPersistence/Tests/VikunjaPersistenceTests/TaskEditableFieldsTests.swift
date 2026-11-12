import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct TaskEditableFieldsTests {
    @Test
    func `wire precision empty descriptions and reminder ordering do not create conflicts`() {
        let projectID = UUID()
        let first = TaskReminder(reminder: Date(timeIntervalSince1970: 1000.8))
        let second = TaskReminder(reminder: Date(timeIntervalSince1970: 2000.2))
        var task = VikunjaTask(
            id: 10, title: "Task", dueDate: Date(timeIntervalSince1970: 3000.5), projectID: 1,
            reminders: [first, second],
        )
        let base = TaskEditableFields(task, projectLocalID: projectID)
        task.description = ""
        task.dueDate = Date(timeIntervalSince1970: 3000)
        task.reminders = [
            TaskReminder(reminder: Date(timeIntervalSince1970: 2000)),
            TaskReminder(reminder: Date(timeIntervalSince1970: 1000)),
        ]
        #expect(base == TaskEditableFields(task, projectLocalID: projectID))
    }

    @Test
    func `relative reminder definitions are compared independently of their derived timestamp`() {
        let projectID = UUID()
        var task = VikunjaTask(
            id: 10, title: "Task", projectID: 1,
            reminders: [TaskReminder(
                reminder: Date(timeIntervalSince1970: 1000), relativePeriod: -60, relativeTo: .dueDate,
            )],
        )
        let base = TaskEditableFields(task, projectLocalID: projectID)
        task.reminders[0].reminder = Date(timeIntervalSince1970: 5000)
        #expect(base == TaskEditableFields(task, projectLocalID: projectID))
        task.reminders[0].relativePeriod = -120
        #expect(base != TaskEditableFields(task, projectLocalID: projectID))
    }

    @Test
    func `evaluation distinguishes unchanged already applied and conflicting task fields`() {
        let projectID = UUID()
        let task = VikunjaTask(id: 10, title: "Task", projectID: 1)
        let base = TaskEditableFields(task, projectLocalID: projectID)
        var desired = base
        desired.priority = 3
        #expect(TaskEditEvaluation.compare(base: base, desired: desired, current: base) == .unchanged)
        #expect(TaskEditEvaluation.compare(base: base, desired: desired, current: desired) == .alreadyApplied)
        var external = base
        external.title = "External edit"
        #expect(TaskEditEvaluation.compare(base: base, desired: desired, current: external) == .conflict)
        #expect(TaskEditEvaluation.compare(base: base, desired: desired, current: nil) == .conflict)
    }

    @Test
    func `legacy payloads decode without inventing a baseline`() throws {
        let json = """
        {"title":"Task","isDone":false,"priority":0,"projectLocalID":"00000000-0000-0000-0000-000000000001"}
        """
        let payload = try JSONDecoder().decode(TaskCreateOrUpdatePayload.self, from: Data(json.utf8))
        #expect(payload.baseFields == nil)
        #expect(payload.baseUpdatedAt == nil)
    }
}
