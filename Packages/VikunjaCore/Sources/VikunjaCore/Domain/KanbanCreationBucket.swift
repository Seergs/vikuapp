/// A cached destination for a rejected creation; capacity excludes the task being recovered.
public struct KanbanCreationBucket: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let isFull: Bool

    public init(id: Int, title: String, isFull: Bool) {
        self.id = id
        self.title = title
        self.isFull = isFull
    }
}
