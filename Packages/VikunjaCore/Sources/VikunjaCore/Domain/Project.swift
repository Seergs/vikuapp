import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public let id: Int
    public var title: String
    public var description: String?
    public var isArchived: Bool
    public var isFavorite: Bool
    public var parentProjectID: Int?
    public var position: Double
    public var hexColor: String

    public init(
        id: Int,
        title: String,
        description: String? = nil,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        parentProjectID: Int? = nil,
        position: Double = 0,
        hexColor: String = "",
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.parentProjectID = parentProjectID
        self.position = position
        self.hexColor = hexColor
    }

    public var kind: ProjectKind {
        if id == -1 {
            return .favorites
        }
        if id < 0 {
            return .savedFilter
        }
        return .project
    }
}
