import Foundation
@testable import Kanban
import Testing
import VikunjaCore

struct KanbanColumnContentTests {
    @Test(arguments: [0, -1])
    func `unlimited buckets have no capacity bar`(limit: Int) {
        let bucket = KanbanBucket(id: 1, title: "Work", limit: limit, tasks: [task(1)])
        #expect(KanbanColumnContent(bucket: bucket, searchText: "").capacityFraction == nil)
    }

    @Test(arguments: [0, 1, 2, 3])
    func `capacity fills up to the limit without overflowing`(count: Int) {
        let bucket = KanbanBucket(id: 1, title: "Work", limit: 2, tasks: (0 ..< count).map { task($0) })
        let content = KanbanColumnContent(bucket: bucket, searchText: "")
        #expect(content.capacityFraction == min(Double(count) / 2, 1))
        #expect(content.visibleTasks == bucket.tasks)
        #expect(bucket.isFull == (count >= 2))
    }

    @Test func `search filters cards without changing capacity`() {
        let bucket = KanbanBucket(id: 1, title: "Work", limit: 2, tasks: [
            task(1, title: "Write proposal"), task(2, title: "Review design"),
        ])
        let content = KanbanColumnContent(bucket: bucket, searchText: "PROPOSAL")
        #expect(content.visibleTasks.map(\.id) == [.remote(1)])
        #expect(content.capacityFraction == 1)
        #expect(bucket.isFull)
    }

    @Test func `no search matches keeps actual capacity visible`() {
        let bucket = KanbanBucket(id: 1, title: "Work", limit: 2, tasks: [task(1)])
        let content = KanbanColumnContent(bucket: bucket, searchText: "Missing")
        #expect(content.visibleTasks.isEmpty)
        #expect(content.capacityFraction == 0.5)
    }

    @Test func `pending local tasks reserve capacity and removing them restores it`() {
        var bucket = KanbanBucket(id: 1, title: "Work", limit: 2, tasks: [task(1)])
        let pending = VikunjaTask(id: .local(UUID()), title: "Offline task", projectID: 1)
        bucket.tasks.append(pending)
        #expect(KanbanColumnContent(bucket: bucket, searchText: "").capacityFraction == 1)
        #expect(bucket.isFull)
        bucket.tasks.removeAll { $0.id == pending.id }
        #expect(KanbanColumnContent(bucket: bucket, searchText: "").capacityFraction == 0.5)
        #expect(!bucket.isFull)
    }

    private func task(_ id: Int, title: String = "Task") -> VikunjaTask {
        VikunjaTask(id: .remote(id), title: title, projectID: 1)
    }
}
