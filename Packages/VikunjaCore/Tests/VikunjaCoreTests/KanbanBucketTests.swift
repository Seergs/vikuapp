import Testing
@testable import VikunjaCore

struct KanbanBucketTests {
    @Test
    func `defaults to not done, no wip limit, and no tasks`() {
        let bucket = KanbanBucket(id: 1, title: "To Do")

        #expect(bucket.isDoneBucket == false)
        #expect(bucket.limit == 0)
        #expect(bucket.tasks.isEmpty)
    }

    @Test
    func `equality is based on all fields, not just id`() {
        let task = VikunjaTask(id: 1, title: "Buy coffee", projectID: 4)
        let bucket = KanbanBucket(id: 1, title: "Done", isDoneBucket: true, limit: 3, tasks: [task])
        let sameFields = KanbanBucket(id: 1, title: "Done", isDoneBucket: true, limit: 3, tasks: [task])
        let differentTitle = KanbanBucket(id: 1, title: "In Progress", isDoneBucket: true, limit: 3, tasks: [task])

        #expect(bucket == sameFields)
        #expect(bucket != differentTitle)
    }

    @Test
    func `carries its nested tasks`() {
        let tasks = [
            VikunjaTask(id: 1, title: "Buy coffee", projectID: 4),
            VikunjaTask(id: 2, title: "Write tests", projectID: 4),
        ]
        let bucket = KanbanBucket(id: 1, title: "To Do", tasks: tasks)

        #expect(bucket.tasks.map(\.id) == [1, 2])
    }
}
