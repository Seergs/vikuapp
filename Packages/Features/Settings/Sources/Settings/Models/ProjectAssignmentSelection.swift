import Foundation
import VikunjaCore

/// Disabled is represented by the webhook event, not a relay filter value.
enum ProjectAssignmentSelection: CaseIterable {
    case disabled
    case onlyMe
    case all

    var title: String {
        switch self {
        case .disabled: String(localized: "Do Not Notify", bundle: .module)
        case .onlyMe: String(localized: "Only Me", bundle: .module)
        case .all: String(localized: "Anyone", bundle: .module)
        }
    }

    var relayMode: AssignmentNotificationMode? {
        switch self {
        case .disabled: nil
        case .onlyMe: .onlyMe
        case .all: .all
        }
    }
}
