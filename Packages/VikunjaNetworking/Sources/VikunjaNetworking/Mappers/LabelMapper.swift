import VikunjaCore

enum LabelMapper {
    static func toDomain(_ dto: LabelDTO) -> Label {
        Label(id: .remote(dto.id), title: dto.title, hexColor: dto.hexColor)
    }

    static func toDTO(_ label: Label) -> LabelDTO {
        LabelDTO(
            // Ignored by the server on create, which is the only path that can
            // ever hand this a `.local` id (see VikunjaLabelRepository.update).
            id: label.id.remoteValue ?? 0,
            title: label.title,
            hexColor: label.hexColor,
        )
    }
}
