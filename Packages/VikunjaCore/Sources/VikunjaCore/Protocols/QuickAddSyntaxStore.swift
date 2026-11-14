/// Observable, account-bound access used by Settings and title parsers.
@MainActor
public protocol QuickAddSyntaxStore: AnyObject {
    /// `nil` when shortcuts are off or the first account snapshot is unavailable.
    var syntax: QuickAddSyntax? { get }
    var hasKnownMode: Bool { get }
    var syncStatus: SyncItemStatus? { get }
    var failureMessage: String? { get }
    func retrySync()
    func setSyntax(_ syntax: QuickAddSyntax?)
}

public extension QuickAddSyntaxStore {
    var hasKnownMode: Bool {
        true
    }

    var syncStatus: SyncItemStatus? {
        nil
    }

    var failureMessage: String? {
        nil
    }

    func retrySync() {}
}
