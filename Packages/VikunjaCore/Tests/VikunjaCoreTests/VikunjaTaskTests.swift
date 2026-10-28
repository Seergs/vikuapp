import Testing
@testable import VikunjaCore

struct VikunjaTaskTests {
    @Test
    func `defaults to unset priority and no labels`() {
        let task = VikunjaTask(id: 1, title: "Buy coffee", projectID: 4)

        #expect(task.priority == .unset)
        #expect(task.labels.isEmpty)
        #expect(task.isDone == false)
    }

    @Test
    func `defaults to no relations`() {
        let task = VikunjaTask(id: 1, title: "Buy coffee", projectID: 4)

        #expect(task.subtasks.isEmpty)
        #expect(task.dependsOn.isEmpty)
        #expect(task.blocks.isEmpty)
        #expect(task.isBlocked == false)
    }

    @Test
    func `is blocked when any depends on task is not done`() {
        let task = VikunjaTask(
            id: 1,
            title: "Ship release",
            projectID: 4,
            dependsOn: [
                TaskRelation(id: 2, title: "Write tests", isDone: true, projectID: 4),
                TaskRelation(id: 3, title: "Fix bug", isDone: false, projectID: 4),
            ],
        )

        #expect(task.isBlocked == true)
    }

    @Test
    func `is not blocked when every depends on task is done`() {
        let task = VikunjaTask(
            id: 1,
            title: "Ship release",
            projectID: 4,
            dependsOn: [TaskRelation(id: 2, title: "Write tests", isDone: true, projectID: 4)],
        )

        #expect(task.isBlocked == false)
    }

    @Test
    func `add relation routes each kind into its matching collection`() {
        var task = VikunjaTask(id: 1, title: "Buy coffee", projectID: 4)

        task.addRelation(TaskRelation(id: 2, title: "Child", projectID: 4), kind: .subtask)
        task.addRelation(TaskRelation(id: 3, title: "Dependency", projectID: 4), kind: .blocked)
        task.addRelation(TaskRelation(id: 4, title: "Dependent", projectID: 4), kind: .blocking)
        task.addRelation(TaskRelation(id: 5, title: "Related", projectID: 4), kind: .related)

        #expect(task.subtasks.map(\.id) == [2])
        #expect(task.dependsOn.map(\.id) == [3])
        #expect(task.blocks.map(\.id) == [4])
        #expect(task.otherRelations[.related]?.map(\.id) == [5])
        #expect(task.hasRelations)
    }

    @Test
    func `priority display name folds do now into urgent`() {
        #expect(VikunjaTask.Priority.unset.displayName == "None")
        #expect(VikunjaTask.Priority.low.displayName == "Low")
        #expect(VikunjaTask.Priority.medium.displayName == "Medium")
        #expect(VikunjaTask.Priority.high.displayName == "High")
        #expect(VikunjaTask.Priority.urgent.displayName == "Urgent")
        #expect(VikunjaTask.Priority.doNow.displayName == "Urgent")
    }

    @Test
    func `selectable priorities exclude do now`() {
        #expect(VikunjaTask.Priority.selectable == [.unset, .low, .medium, .high, .urgent])
    }
}
