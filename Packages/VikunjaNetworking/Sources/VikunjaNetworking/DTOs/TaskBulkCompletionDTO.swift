/// Deliberately narrower than TaskDTO: the bulk endpoint must receive an
/// explicit field list and must never overwrite unrelated task properties.
struct TaskBulkCompletionRequestDTO: Encodable, Sendable {
    let taskIDs: [Int]
    private let fields = ["done"]
    let values: Values

    struct Values: Encodable, Sendable {
        let done: Bool
    }

    init(taskIDs: [Int], isDone: Bool) {
        self.taskIDs = taskIDs
        self.values = Values(done: isDone)
    }

    enum CodingKeys: String, CodingKey {
        case taskIDs = "task_ids"
        case fields
        case values
    }
}

/// Both modern v1 and v2 handlers return a BulkTask object containing `tasks`,
/// despite v1's swagger annotation describing the response as a task array.
struct TaskBulkCompletionResponseDTO: Decodable, Sendable {
    let tasks: [TaskDTO]
}
