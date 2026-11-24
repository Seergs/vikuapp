import VikunjaCore

enum ProjectMapper {
    /// The server appends virtual projects outside pagination on every page.
    /// Preserve first-seen ordering and keep each virtual identity only once.
    static func catalogToDomain(_ dtos: [ProjectDTO]) -> [Project] {
        var virtualIDs: Set<Int> = []
        return dtos.filter { $0.id >= 0 || virtualIDs.insert($0.id).inserted }.map(toDomain)
    }

    static func toDomain(_ dto: ProjectDTO) -> Project {
        Project(
            id: .remote(dto.id),
            title: dto.title,
            description: dto.description,
            isArchived: dto.isArchived ?? false,
            isFavorite: dto.isFavorite ?? false,
            // The API can return zero or omit the parent for root-level projects.
            parentProjectID: (dto.parentProjectId == 0 ? nil : dto.parentProjectId).map(EntityID.remote),
            position: dto.position ?? 0,
            hexColor: dto.hexColor ?? "",
            updated: dto.updated,
        )
    }

    static func toDTO(_ project: Project, forUpdate: Bool = false) -> ProjectDTO {
        // An update must send zero to detach a project. An omitted parent
        // leaves the existing relationship intact on newer servers.
        let rootParentID: Int? = forUpdate ? 0 : nil
        return ProjectDTO(
            // Ignored by the server on create, which is the only path that can
            // ever hand this a `.local` id (see VikunjaProjectRepository.update).
            id: project.id.remoteValue ?? 0,
            title: project.title,
            description: project.description,
            isArchived: project.isArchived,
            isFavorite: project.isFavorite,
            parentProjectId: project.parentProjectID.map { parentID in
                // A project's own create must resolve before any child
                // project syncs, so a `.local` parent reaching the wire here
                // is an ordering bug upstream, not a value this mapper can
                // encode.
                guard let remoteValue = parentID.remoteValue else {
                    preconditionFailure("Project.toDTO: parent project must be synced before this project can sync")
                }
                return remoteValue
            } ?? rootParentID,
            position: project.position,
            hexColor: project.hexColor,
            // Server-set, read-only — never sent back on write.
            updated: nil,
        )
    }
}
