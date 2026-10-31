@testable import CalendarFeature
import Foundation
import Testing
import VikunjaCore

@MainActor
struct RapidCompletionTests {
    @Test(arguments: [true, false])
    func `a local reload preserves a pending completion until success or rollback`(succeeds: Bool) async {
        let projects = FakeProjectRepository()
        let project = Project(id: 1, title: "Project")
        projects.projects = [project]
        let repository = FakeTaskRepository()
        let first = VikunjaTask(id: 1, title: "First", projectID: 1)
        let second = VikunjaTask(id: 2, title: "Second", projectID: 1)
        repository.tasks = [first, second]
        let model = CalendarViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            taskRepository: repository, projectRepository: projects,
        )
        await model.load()
        await model.toggleDone(first)
        // These fakes need not persist updates; seed the first saved edit.
        repository.tasks[0].isDone = true
        repository.updateError = succeeds ? nil : .network("Write failed")
        repository.beforeUpdate = {
            let optimistic = await model.tasks.map(\.isDone)
            #expect(optimistic == [true, true])
            repository.tasks[1].title = "Renamed during the write"
            await model.load()
            let reloaded = await model.tasks.map(\.isDone)
            #expect(reloaded == [true, true])
        }
        await model.toggleDone(second)
        #expect(model.tasks.map(\.isDone) == [true, succeeds])
        #expect(model.tasks[1].title == "Renamed during the write")
        repository.beforeUpdate = nil
        repository.tasks[1].isDone = succeeds
        await model.load()
        #expect(model.tasks.map(\.isDone) == [true, succeeds])
    }
}
