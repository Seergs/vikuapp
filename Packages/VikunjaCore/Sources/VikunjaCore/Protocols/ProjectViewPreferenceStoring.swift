/// The view a project or saved filter should open on this device.
public enum ProjectViewSelection: Codable, Equatable, Sendable {
    case list
    case kanban(boardID: Int?)
}

@MainActor
public protocol ProjectViewPreferenceStoring {
    func selection(for projectID: EntityID) -> ProjectViewSelection?
    func setSelection(_ selection: ProjectViewSelection, for projectID: EntityID)
}
