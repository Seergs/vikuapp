/// What a ViewModel and Settings need in order to read and change the
/// shortcut dialect quick-add parses (`QuickAddSyntax`), without knowing
/// where it's persisted. Implemented by a `UserDefaults`-backed store in the
/// app target and injected via `AppContainer`, the same way `TaskSortStore` is.
@MainActor
public protocol QuickAddSyntaxStore: AnyObject {
    var syntax: QuickAddSyntax { get }
    func setSyntax(_ syntax: QuickAddSyntax)
}
