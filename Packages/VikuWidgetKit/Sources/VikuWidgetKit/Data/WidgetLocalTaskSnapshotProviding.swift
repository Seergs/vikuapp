import Foundation
import VikunjaPersistence

/// Supplies the offline fallback for both widget loaders. Tests inject a fake;
/// `VikuWidgetEnvironment` wires the real App Group database reader.
public protocol WidgetLocalTaskSnapshotProviding: Sendable {
    /// - Parameter accountID: the active account, or `nil` when the widget
    ///   cannot read the keychain. The reader then resolves a single stored
    ///   account when that is unambiguous.
    func loadSnapshot(accountID: UUID?) async -> LocalTaskSnapshot?
}

/// Adapts the persistence layer's read-only snapshot reader to the widget
/// module's dependency contract.
public struct LocalStoreWidgetSnapshotProvider: WidgetLocalTaskSnapshotProviding {
    private let reader: LocalTaskSnapshotReader

    public init(localStore: LocalStore) {
        self.reader = LocalTaskSnapshotReader(localStore: localStore)
    }

    public func loadSnapshot(accountID: UUID?) async -> LocalTaskSnapshot? {
        try? await reader.loadSnapshot(accountID: accountID)
    }
}
