import VikunjaCore

enum ProjectMapper {
    static func toDomain(_ dto: ProjectDTO) -> Project {
        Project(
            id: .remote(dto.id),
            title: dto.title,
            description: dto.description,
            isArchived: dto.isArchived ?? false,
            isFavorite: dto.isFavorite ?? false,
            // The real API's `parent_project_id` is a non-pointer `int64` on the
            // server, so root-level projects come back as `0`, never absent/null —
            // normalize that to `nil` so `ProjectsListViewModel` can treat "no
            // parent" as a single, unambiguous value.
            parentProjectID: (dto.parentProjectId == 0 ? nil : dto.parentProjectId).map(EntityID.remote),
            position: dto.position ?? 0,
            hexColor: dto.hexColor ?? "",
            updated: dto.updated,
        )
    }

    static func toDTO(_ project: Project) -> ProjectDTO {
        ProjectDTO(
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
            },
            position: project.position,
            hexColor: project.hexColor,
            // Server-set, read-only — never sent back on write.
            updated: nil,
        )
    }
}
