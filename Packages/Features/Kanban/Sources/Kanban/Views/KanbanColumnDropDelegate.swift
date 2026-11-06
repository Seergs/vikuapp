import SwiftUI
import UniformTypeIdentifiers
import VikunjaCore

/// Owns the column's entire drop lifecycle instead of delegating insertion to
/// a List. Capacity is checked before iOS proposes an accepted operation.
struct KanbanColumnDropDelegate: DropDelegate {
    static let contentTypes: [UTType] = [.utf8PlainText]

    let bucketID: Int
    let allowsDrop: Bool
    @Binding var target: KanbanDropTarget
    let onDropTaskID: @MainActor @Sendable (EntityID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        allowsDrop && info.hasItemsConforming(to: Self.contentTypes)
    }

    func dropEntered(info: DropInfo) {
        target.update(isTargeted: allowsDrop, bucketID: bucketID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: allowsDrop ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        target.update(isTargeted: false, bucketID: bucketID)
    }

    func performDrop(info: DropInfo) -> Bool {
        target.reset()
        guard allowsDrop,
              let provider = info.itemProviders(for: Self.contentTypes).first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        let onDropTaskID = onDropTaskID
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String,
                  let taskID = KanbanDragIdentity.decode(value) else { return }
            Task { @MainActor in onDropTaskID(taskID) }
        }
        return true
    }
}
