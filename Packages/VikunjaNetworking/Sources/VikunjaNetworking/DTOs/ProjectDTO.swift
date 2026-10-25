import Foundation

struct ProjectDTO: Codable {
    let id: Int
    let title: String
    let description: String?
    let isArchived: Bool?
    let isFavorite: Bool?
    let parentProjectId: Int?
    let position: Double?
    let hexColor: String?
    let updated: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case position
        case isArchived = "is_archived"
        case isFavorite = "is_favorite"
        case parentProjectId = "parent_project_id"
        case hexColor = "hex_color"
        case updated
    }
}
