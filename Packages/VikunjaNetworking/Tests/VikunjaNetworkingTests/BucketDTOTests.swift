import Foundation
import Testing
@testable import VikunjaNetworking

struct BucketDTOTests {
    @Test
    func `decodes buckets with their nested tasks`() throws {
        let response = try loadBucketsWithTasks()

        #expect(response.items.map(\.id) == [20, 22])
        #expect(response.items[0].title == "To Do")
        #expect(response.items[0].tasks?.map(\.title) == ["Write proposal"])
        #expect(response.items[1].limit == 3)
    }

    @Test
    func `maps a bucket to the domain model, flagging the done bucket by id`() throws {
        let response = try loadBucketsWithTasks()
        let doneBucketID = 22

        let buckets = response.items.map { BucketMapper.toDomain($0, isDoneBucket: $0.id == doneBucketID) }

        #expect(buckets[0].isDoneBucket == false)
        #expect(buckets[1].isDoneBucket == true)
        #expect(buckets[1].tasks.first?.isDone == true)
    }

    @Test
    func `resolves the kanban view by kind, ignoring other views`() throws {
        let url = try #require(Bundle.module.url(forResource: "project-views", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(APIv2Envelope<ProjectViewDTO>.self, from: data)

        let kanbanView = envelope.items.first { $0.viewKind == "kanban" }

        #expect(kanbanView?.id == 11)
        #expect(kanbanView?.doneBucketId == 22)
    }

    private func loadBucketsWithTasks() throws -> BucketsWithTasksResponseDTO {
        let url = try #require(Bundle.module.url(forResource: "buckets-with-tasks", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BucketsWithTasksResponseDTO.self, from: data)
    }
}
