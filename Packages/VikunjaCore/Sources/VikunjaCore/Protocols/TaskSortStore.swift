/// What a ViewModel needs to read and change task sort preferences,
/// without knowing anything about where they're persisted. Implemented
/// by a `UserDefaults`-backed store in the app target and injected via
/// `AppContainer`.
@MainActor
public protocol TaskSortStore: AnyObject {
    var taskSort: TaskSort { get }
    func setTaskSort(_ sort: TaskSort)
}
