import Foundation

public struct KanbanBucket: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public var title: String
    public var isDoneBucket: Bool
    public var limit: Int
    public var tasks: [VikunjaTask]

    public init(
        id: Int,
        title: String,
        isDoneBucket: Bool = false,
        limit: Int = 0,
        tasks: [VikunjaTask] = [],
    ) {
        self.id = id
        self.title = title
        self.isDoneBucket = isDoneBucket
        self.limit = limit
        self.tasks = tasks
    }
}
