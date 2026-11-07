import Foundation
import Testing
import VikunjaCore

struct TaskCommentTests {
    @Test(arguments: [(0.0, false), (1.0, true), (3600.0, true), (-1.0, false)])
    func `edited indicator requires an update after creation`(
        updateOffset: TimeInterval, expected: Bool,
    ) {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let comment = TaskComment(
            id: .remote(1), comment: "A comment", author: User(id: 1, username: "alex"),
            created: created, updated: created.addingTimeInterval(updateOffset),
        )

        #expect(comment.isEdited == expected)
    }
}
