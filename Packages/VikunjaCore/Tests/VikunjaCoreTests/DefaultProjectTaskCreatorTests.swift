import Foundation
import Testing
import VikunjaCore

@Suite("DefaultProjectTaskCreator")
struct DefaultProjectTaskCreatorTests {
    private let inbox = Project(id: 42, title: "Inbox")
    private let projects = FakeProjectRepository()
    private let tasks = FakeTaskRepository()

    private var creator: DefaultProjectTaskCreator {
        DefaultProjectTaskCreator(projectRepository: projects, taskRepository: tasks)
    }

    @Test
    func `saves exactly one task with a literal title in the configured project`() async throws {
        projects.projects = [Project(id: 1, title: "Work"), inbox]

        let result = try await creator.create(title: "  Get an insurance quote #urgent  ", defaultProjectID: 42)

        #expect(result.project == inbox)
        #expect(result.task.projectID == inbox.id)
        #expect(result.task.title == "Get an insurance quote #urgent")
        #expect(tasks.tasks == [result.task])
    }

    @Test
    func `asks for a title again when dictation is blank`() async {
        projects.projects = [inbox]

        await #expect(throws: DefaultProjectTaskCreator.Failure.emptyTitle) {
            try await creator.create(title: " \n ", defaultProjectID: 42)
        }
        #expect(tasks.tasks.isEmpty)
    }

    @Test
    func `requires a configured project even if Inbox exists`() async {
        projects.projects = [inbox]

        await #expect(throws: DefaultProjectTaskCreator.Failure.missingDefaultProject) {
            try await creator.create(title: "Get a quote", defaultProjectID: nil)
        }
        #expect(tasks.tasks.isEmpty)
    }

    @Test(arguments: [17, 43, -1])
    func `rejects missing archived and virtual destinations`(projectID: Int) async {
        projects.projects = [
            inbox, Project(id: 43, title: "Archive", isArchived: true), Project(id: -1, title: "Favorites"),
        ]

        await #expect(throws: DefaultProjectTaskCreator.Failure.unavailableDefaultProject) {
            try await creator.create(title: "Get a quote", defaultProjectID: projectID)
        }
        #expect(tasks.tasks.isEmpty)
    }

    @Test
    func `propagates save failure without reporting creation`() async {
        projects.projects = [inbox]
        tasks.createError = .bucketFull

        await #expect(throws: VikunjaError.bucketFull) {
            try await creator.create(title: "Get a quote", defaultProjectID: 42)
        }
        #expect(tasks.tasks.isEmpty)
    }

    @Test
    func `cancellation before the write leaves the destination empty`() async {
        projects.projects = [inbox]

        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await creator.create(title: "Get a quote", defaultProjectID: 42)
        }
        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
        #expect(tasks.tasks.isEmpty)
    }
}
