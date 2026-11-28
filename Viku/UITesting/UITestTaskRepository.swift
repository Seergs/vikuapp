#if DEBUG
import Foundation
import VikunjaCore

actor UITestTaskRepository: TaskRepositoryProtocol, TaskBulkUpdateRepositoryProtocol {
    private let file: UITestStateFile<UITestServerCollection<ServerTask>>
    private var state: UITestServerCollection<ServerTask>

    init(directory: URL, seed: UITestScenario?, secondInstance: Bool) throws {
        let file = UITestStateFile<UITestServerCollection<ServerTask>>(
            url: directory.appendingPathComponent("tasks.json"),
        )
        self.state = try file.load(seed: seed.map { scenario in
            let tasks = scenario == .empty ? [] : UITestFixtures.tasks(secondInstance: secondInstance)
            return try UITestServerCollection(records: tasks.map { try ServerTask($0) })
        })
        self.file = file
    }

    func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        state.records.filter { $0.projectID == projectID.remoteValue }.map(\.model)
    }

    func fetchTask(id: EntityID) async throws -> VikunjaTask {
        guard let task = state.records.first(where: { $0.id == id.remoteValue }) else { throw VikunjaError.notFound }
        return task.model
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        state.records.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.map(\.model)
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        try file.update(&state) {
            let created = try ServerTask(task, id: $0.nextID, updated: Date())
            $0.nextID += 1
            $0.records.append(created)
            return created.model
        }
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        guard let index = state.records.firstIndex(where: { $0.id == task.id.remoteValue }) else {
            throw VikunjaError.notFound
        }
        let updated = try ServerTask(task, updated: Date())
        try file.update(&state) { $0.records[index] = updated }
        return updated.model
    }

    func delete(id: EntityID) async throws {
        try file.update(&state) { $0.records.removeAll { $0.id == id.remoteValue } }
    }

    func apply(_ change: TaskBulkChange, toTaskIDs taskIDs: [EntityID]) async throws -> [VikunjaTask] {
        let ids = try Set(taskIDs.map { try $0.requiredUITestRemoteID() })
        guard ids.isSubset(of: Set(state.records.map(\.id))) else { throw VikunjaError.notFound }
        return try file.update(&state) { state in
            let updated = Date()
            return state.records.indices.filter { ids.contains(state.records[$0].id) }.map { index in
                switch change {
                case let .completion(isDone): state.records[index].isDone = isDone
                case let .dueDate(date): state.records[index].dueDate = date
                }
                state.records[index].updated = updated
                return state.records[index].model
            }
        }
    }
}

private nonisolated struct ServerTask: Codable, Sendable {
    let id: Int
    let title: String
    let description: String?
    var isDone: Bool
    var dueDate: Date?
    let priority: Int
    let projectID: Int
    let labels: [ServerLabel]
    let relations: [RelationKind: [ServerRelation]]
    let reminders: [TaskReminder]
    var updated: Date?

    init(_ task: VikunjaTask, id: Int? = nil, updated: Date? = nil) throws {
        self.id = try id ?? task.id.requiredUITestRemoteID()
        self.title = task.title
        self.description = task.description
        self.isDone = task.isDone
        self.dueDate = task.dueDate
        self.priority = task.priority.rawValue
        self.projectID = try task.projectID.requiredUITestRemoteID()
        self.labels = try task.labels.map(ServerLabel.init)
        var relations = task.otherRelations
        relations[.subtask] = task.subtasks
        relations[.blocked] = task.dependsOn
        relations[.blocking] = task.blocks
        self.relations = try relations.mapValues { try $0.map(ServerRelation.init) }
        self.reminders = task.reminders
        self.updated = updated ?? task.updated
    }

    var model: VikunjaTask {
        var relations = relations.mapValues { $0.map(\.model) }
        let subtasks = relations.removeValue(forKey: .subtask) ?? []
        let dependsOn = relations.removeValue(forKey: .blocked) ?? []
        let blocks = relations.removeValue(forKey: .blocking) ?? []
        return VikunjaTask(
            id: .remote(id), title: title, description: description, isDone: isDone, dueDate: dueDate,
            priority: VikunjaTask.Priority(rawValue: priority) ?? .unset, projectID: .remote(projectID),
            labels: labels.map(\.model), subtasks: subtasks, dependsOn: dependsOn, blocks: blocks,
            otherRelations: relations, reminders: reminders, updated: updated,
        )
    }
}

private nonisolated struct ServerLabel: Codable, Sendable {
    let id: Int
    let title: String
    let hexColor: String

    init(_ label: Label) throws {
        self.id = try label.id.requiredUITestRemoteID()
        self.title = label.title
        self.hexColor = label.hexColor
    }

    var model: Label {
        Label(id: .remote(id), title: title, hexColor: hexColor)
    }
}

private nonisolated struct ServerRelation: Codable, Sendable {
    let id: Int
    let title: String
    let isDone: Bool
    let projectID: Int

    init(_ relation: TaskRelation) throws {
        self.id = try relation.id.requiredUITestRemoteID()
        self.title = relation.title
        self.isDone = relation.isDone
        self.projectID = try relation.projectID.requiredUITestRemoteID()
    }

    var model: TaskRelation {
        TaskRelation(id: .remote(id), title: title, isDone: isDone, projectID: .remote(projectID))
    }
}
#endif
