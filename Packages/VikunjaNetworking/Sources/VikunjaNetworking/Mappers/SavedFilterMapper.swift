import VikunjaCore

enum SavedFilterMapper {
    static func toDomain(_ dto: SavedFilterDTO) -> SavedFilterDetail {
        SavedFilterDetail(
            id: dto.id,
            title: dto.title,
            description: dto.description ?? "",
            isFavorite: dto.isFavorite ?? false,
            query: dto.filters?.filter ?? "",
        )
    }
}
