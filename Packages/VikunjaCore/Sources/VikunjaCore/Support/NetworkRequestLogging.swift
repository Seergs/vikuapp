import Foundation

/// Session-only, in-memory switch for printing each request's method, path,
/// and response status code to the Xcode console (no bodies), off by
/// default. Lives in `VikunjaCore` (rather than `VikunjaNetworking`) so
/// every package that talks HTTP directly can log through the same switch
/// instead of each having its own, `VikunjaNetworking`'s `URLSessionAPIClient`
/// and `VikuAuth`'s `RelayPushRegistrationService` included. The app target
/// only ever exposes a way to flip it from a dev-build-only Settings toggle
/// (`DevToolsCenter`, bridging `NetworkRequestLoggingStoring`), so it stays
/// unreachable, and off, everywhere else.
public final class NetworkRequestLogging: @unchecked Sendable {
    public static let shared = NetworkRequestLogging()

    private let lock = NSLock()
    private var _isEnabled = false

    public var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    private init() {}

    public func log(method: String, path: String, statusCode: Int) {
        guard isEnabled else { return }
        print("🌐 \(method) \(path) → \(statusCode)")
    }
}
