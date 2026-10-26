import Foundation

public struct Label: Identifiable, Equatable, Hashable, Sendable {
    public let id: EntityID
    public var title: String
    public var hexColor: String

    public init(id: EntityID, title: String, hexColor: String) {
        self.id = id
        self.title = title
        self.hexColor = hexColor
    }
}
