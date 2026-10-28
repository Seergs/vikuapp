import VikunjaCore

enum CommentMapper {
    static func toDomain(_ dto: CommentDTO) -> TaskComment {
        TaskComment(
            id: .remote(dto.id),
            comment: dto.comment,
            author: UserMapper.toDomain(dto.author),
            created: dto.created,
            updated: dto.updated,
        )
    }
}
