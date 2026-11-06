import VikunjaCore

/// Deliberately narrower than TaskDTO: the bulk endpoint must receive an
/// explicit field list and must never overwrite unrelated task properties.
/// `values` carries only the field named in `fields`.
struct TaskBulkUpdateRequestDTO: Encodable, Sendable {
    let taskIDs: [Int]
    let fields: [String]
    let values: Values

    struct Values: Encodable, Sendable {
        var done: Bool?
    }

    init(taskIDs: [Int], change: TaskBulkChange) {
        self.taskIDs = taskIDs
        switch change {
        case let .completion(isDone):
            self.fields = ["done"]
            self.values = Values(done: isDone)
        }
    }

    enum CodingKeys: String, CodingKey {
        case taskIDs = "task_ids"
        case fields
        case values
    }
}

/// Both modern v1 and v2 handlers return a BulkTask object containing `tasks`,
/// despite v1's swagger annotation describing the response as a task array.
struct TaskBulkUpdateResponseDTO: Decodable, Sendable {
    let tasks: [TaskDTO]
}
