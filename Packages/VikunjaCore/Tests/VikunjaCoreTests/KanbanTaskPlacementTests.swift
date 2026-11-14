import Foundation
import Testing
@testable import VikunjaCore

struct KanbanTaskPlacementTests {
    @Test
    func `edge positions order positive and provisional peers without collisions`() throws {
        #expect(try KanbanTaskPlacement.top.position(among: [100, 200]) == 50)
        #expect(try KanbanTaskPlacement.bottom.position(among: [100, 200]) > 200)
        #expect(try KanbanTaskPlacement.top.position(among: [-2, -1, 0]) < -2)
        #expect(try KanbanTaskPlacement.bottom.position(among: [-2, -1, 0]) > 0)
        #expect(try KanbanTaskPlacement.top.position(among: []) > 0)
        #expect(try KanbanTaskPlacement.top.position(among: [Double.leastNonzeroMagnitude]) != 0)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func `non finite peer positions are rejected`(value: Double) {
        #expect(throws: VikunjaError.self) { try KanbanTaskPlacement.top.position(among: [value]) }
        #expect(throws: VikunjaError.self) { try KanbanTaskPlacement.bottom.position(among: [value]) }
    }

    @Test
    func `snapshot resolution uses only peers in the expected bucket`() throws {
        let tasks = (1 ... 3).map { VikunjaTask(id: .remote($0), title: "Task", projectID: 1) }
        let snapshot = KanbanDownload(
            viewID: 10,
            mode: "manual",
            filterQuery: "",
            defaultBucketID: 20,
            doneBucketID: nil,
            buckets: [
                KanbanBucket(id: 20, title: "Bucket", tasks: Array(tasks.prefix(2))),
                KanbanBucket(id: 21, title: "Other", tasks: [tasks[2]]),
            ],
            taskPositions: [1: 100, 2: 200, 3: 1],
        )
        #expect(try KanbanTaskPlacement.top.position(in: snapshot, taskID: 2, bucketID: 20) == 50)
        #expect(try KanbanTaskPlacement.top.position(in: snapshot, taskID: 1, bucketID: 20) == nil)
        #expect(throws: VikunjaError.notFound) {
            try KanbanTaskPlacement.top.position(in: snapshot, taskID: 2, bucketID: 21)
        }
    }
}
