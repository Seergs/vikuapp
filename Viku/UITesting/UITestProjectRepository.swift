#if DEBUG
import Foundation
import VikunjaCore

actor UITestProjectRepository: ProjectRepositoryProtocol {
    private let file: UITestStateFile<UITestServerCollection<ServerProject>>
    private var state: UITestServerCollection<ServerProject>
    private let delaysProjectCreation: Bool

    init(directory: URL, seed: Bool, secondInstance: Bool) throws {
        let arguments = ProcessInfo.processInfo.arguments
        let delayed = arguments.contains("-UITestSlowProjectCreation")
        self.delaysProjectCreation = delayed
        let file = UITestStateFile<UITestServerCollection<ServerProject>>(
            url: directory.appendingPathComponent("projects.json"),
        )
        let projects = seed ? Self.fixtures(
            secondInstance: secondInstance, longList: arguments.contains("-UITestLongProjectList"), delayed: delayed,
        ) : nil
        let initialState = try projects.map { projects in
            try UITestServerCollection(records: projects.map { try ServerProject($0) })
        }
        self.state = try file.load(seed: initialState)
        self.file = file
    }

    private static func fixtures(secondInstance: Bool, longList: Bool, delayed: Bool) -> [Project] {
        if secondInstance {
            return [Project(id: 1, title: "UI Test Second Project")]
        }
        var projects = [
            Project(id: 1, title: "UI Test Project"),
            Project(id: 2, title: "UI Test Context Project"),
            UITestFixtures.savedFilterProject,
        ]
        if longList {
            projects += (3 ... 32).map {
                Project(id: .remote($0), title: "UI Test Project \($0)", position: delayed ? Double($0) : 0)
            }
        }
        return projects
    }

    func fetchProjects() async throws -> [Project] {
        state.records.map(\.model)
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = state.records.first(where: { $0.id == id.remoteValue }) else { throw VikunjaError.notFound }
        return project.model
    }

    func create(_ project: Project) async throws -> Project {
        if delaysProjectCreation {
            try await Task.sleep(for: .seconds(6))
        }
        try Task.checkCancellation()
        return try file.update(&state) {
            let created = try ServerProject(
                project, id: $0.nextID, position: delaysProjectCreation ? 18.5 : project.position, updated: Date(),
            )
            $0.nextID += 1
            $0.records.append(created)
            return created.model
        }
    }

    func update(_ project: Project) async throws -> Project {
        guard let index = state.records.firstIndex(where: { $0.id == project.id.remoteValue }) else {
            throw VikunjaError.notFound
        }
        let updated = try ServerProject(project, updated: Date())
        try file.update(&state) { $0.records[index] = updated }
        return updated.model
    }

    func delete(id: EntityID) async throws {
        try file.update(&state) { $0.records.removeAll { $0.id == id.remoteValue } }
    }
}

private nonisolated struct ServerProject: Codable, Sendable {
    let id: Int
    let title: String
    let description: String?
    let isArchived: Bool
    let isFavorite: Bool
    let parentProjectID: Int?
    let position: Double
    let hexColor: String
    let updated: Date?

    init(_ project: Project, id: Int? = nil, position: Double? = nil, updated: Date? = nil) throws {
        self.id = try id ?? project.id.requiredUITestRemoteID()
        self.title = project.title
        self.description = project.description
        self.isArchived = project.isArchived
        self.isFavorite = project.isFavorite
        self.parentProjectID = try project.parentProjectID?.requiredUITestRemoteID()
        self.position = position ?? project.position
        self.hexColor = project.hexColor
        self.updated = updated ?? project.updated
    }

    var model: Project {
        Project(
            id: .remote(id), title: title, description: description, isArchived: isArchived, isFavorite: isFavorite,
            parentProjectID: parentProjectID.map(EntityID.remote),
            position: position, hexColor: hexColor, updated: updated,
        )
    }
}
#endif
