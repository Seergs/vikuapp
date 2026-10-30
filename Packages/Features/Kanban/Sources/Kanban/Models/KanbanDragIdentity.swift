import Foundation
import VikunjaCore

/// Preserve UUID identity for cards created before their server ID exists.
enum KanbanDragIdentity {
    static func encode(_ id: EntityID) -> String {
        switch id {
        case let .local(uuid): "local:\(uuid.uuidString)"
        case let .remote(value): "remote:\(value)"
        }
    }

    static func decode(_ value: String) -> EntityID? {
        if value.hasPrefix("local:"), let uuid = UUID(uuidString: String(value.dropFirst(6))) {
            return .local(uuid)
        }
        if value.hasPrefix("remote:"), let id = Int(value.dropFirst(7)), id > 0 {
            return .remote(id)
        }
        return nil
    }
}
