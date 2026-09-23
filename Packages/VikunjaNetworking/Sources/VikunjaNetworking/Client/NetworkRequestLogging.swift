import Foundation

/// Session-only, in-memory switch for printing each request's method, path,
/// and response status code to the Xcode console (no bodies), off by
/// default. `VikunjaNetworking` has no notion of dev vs release builds, so
/// this lives unguarded here; the app target only ever exposes a way to
/// flip it from a dev-build-only Settings toggle (`DevToolsCenter`,
/// bridging `VikunjaCore`'s `NetworkRequestLoggingStoring`), so it stays
/// unreachable, and off, everywhere else. `URLSessionAPIClient` checks it
/// on every request.
public final class NetworkRequestLogging: @unchecked Sendable {
    public static let shared = NetworkRequestLogging()

    private let lock = NSLock()
    private var _isEnabled = false

    public var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    private init() {}

    func log(method: String, path: String, statusCode: Int) {
        guard isEnabled else { return }
        print("🌐 \(method) \(path) → \(statusCode)")
    }
}
