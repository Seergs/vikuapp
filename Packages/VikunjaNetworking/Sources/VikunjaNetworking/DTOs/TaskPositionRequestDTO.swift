struct TaskPositionRequestDTO: Encodable {
    let projectViewID: Int
    let position: Double

    enum CodingKeys: String, CodingKey {
        case projectViewID = "project_view_id"
        case position
    }
}

struct TaskPositionResponseDTO: Decodable, Sendable {
    let taskID: Int
    let viewID: Int
    let position: Double

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case viewID = "project_view_id"
        case position
    }
}
