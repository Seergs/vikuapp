import VikunjaCore

enum TaskRelationMapper {
    /// `fallbackProjectID` covers a `RelatedTaskDTO` whose own `project_id`
    /// is missing — most commonly a subtask, which in practice sits in the
    /// same project as its parent.
    static func toDomain(_ dto: RelatedTaskDTO, fallbackProjectID: Int) -> TaskRelation {
        TaskRelation(
            id: .remote(dto.id), title: dto.title, isDone: dto.done,
            projectID: .remote(dto.projectId ?? fallbackProjectID),
        )
    }
}
