import VikunjaCore

enum BucketMapper {
    /// `isDoneBucket` isn't on `BucketDTO` itself — it's derived by the
    /// caller comparing `dto.id` against the owning view's
    /// `ProjectViewDTO.doneBucketId`.
    static func toDomain(_ dto: BucketDTO, isDoneBucket: Bool) -> KanbanBucket {
        KanbanBucket(
            id: dto.id,
            title: dto.title,
            isDoneBucket: isDoneBucket,
            limit: dto.limit,
            tasks: (dto.tasks ?? []).map(TaskMapper.toDomain),
        )
    }
}
