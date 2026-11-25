import Foundation
import VikunjaCore

/// Stores presentation preferences on this device, scoped to one signed-in account.
struct ProjectViewPreferenceStore: ProjectViewPreferenceStoring {
    let defaults: UserDefaults
    let accountID: UUID

    func selection(for projectID: EntityID) -> ProjectViewSelection? {
        guard let data = defaults.data(forKey: key(for: projectID)) else { return nil }
        return try? JSONDecoder().decode(ProjectViewSelection.self, from: data)
    }

    func setSelection(_ selection: ProjectViewSelection, for projectID: EntityID) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key(for: projectID))
    }

    private func key(for projectID: EntityID) -> String {
        let entityKey = switch projectID {
        case let .remote(id): "remote.\(id)"
        case let .local(id): "local.\(id.uuidString)"
        }
        return "projectView.\(accountID.uuidString).\(entityKey)"
    }
}
