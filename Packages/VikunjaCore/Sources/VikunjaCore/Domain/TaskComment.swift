import Foundation

/// A comment posted on a task, in the order Vikunja returns them.
public struct TaskComment: Identifiable, Equatable, Sendable {
    public let id: EntityID
    public var comment: String
    public var author: User
    public var created: Date
    public var updated: Date

    /// Both server responses and pending local edits preserve these timestamps.
    public var isEdited: Bool {
        updated > created
    }

    public init(id: EntityID, comment: String, author: User, created: Date, updated: Date) {
        self.id = id
        self.comment = comment
        self.author = author
        self.created = created
        self.updated = updated
    }
}
