/// What a view needs in order to read and change whether network requests
/// (method, path, response status code, no bodies) get printed to the
/// Xcode console, without knowing anything about `VikunjaNetworking`
/// (`Features/*` never imports it directly). Deliberately session-only,
/// same as `DevBadgeVisibilityStoring`: not expected to persist anywhere,
/// just held for the life of the app process. Implemented by the app
/// target's `DevToolsCenter`, which bridges the setter through to
/// `VikunjaNetworking`'s actual logging switch, and injected via
/// `AppContainer`.
@MainActor
public protocol NetworkRequestLoggingStoring: AnyObject {
    var isNetworkRequestLoggingEnabled: Bool { get }
    func setNetworkRequestLoggingEnabled(_ enabled: Bool)
}
