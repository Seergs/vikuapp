import Foundation

/// Drives an instance's OIDC login through the provider's own authorization
/// page, presented in a system browser session. The concrete implementation
/// (`VikuAuth`'s `OIDCAuthCoordinator`) resolves its own presentation
/// anchor, so this protocol carries no UIKit/SwiftUI dependency — matching
/// `ToastPresenting`/`HapticFeedbackPresenting`.
public protocol OIDCAuthenticating: Sendable {
    /// Presents `provider`'s authorization page and waits for the user to
    /// complete or cancel it, returning the raw authorization code. Vikunja's
    /// backend, not this call, exchanges it for a session — see
    /// `AuthServiceProtocol.loginWithOIDC`.
    ///
    /// - Parameter redirectURI: This app's own callback URI (e.g.
    ///   `viku://oidc-callback`). Must be registered as an additional
    ///   redirect URI on the provider's client alongside the instance's own
    ///   web frontend — Vikunja's backend accepts whatever redirect URI the
    ///   client used, as long as the provider itself accepts it.
    @MainActor
    func authenticate(provider: OIDCProvider, redirectURI: URL) async throws -> String
}

/// Errors an `OIDCAuthenticating` conformance can throw. Lives alongside the
/// protocol (rather than in `VikuAuth`, which implements it) so Features can
/// pattern-match `.canceled` without importing `VikuAuth` — the same
/// relationship `VikunjaError` has to `VikunjaNetworking`.
public enum OIDCAuthError: Error, Sendable, Equatable {
    /// The user dismissed the browser session before completing sign-in —
    /// not a failure, callers should treat this as "nothing happened"
    /// rather than surface an error banner.
    case canceled
    /// No foreground window to present the authorization page from.
    case noPresentingViewController
    /// The browser session couldn't be started (e.g. Guided Access is on).
    case presentationUnavailable
    case missingAuthorizationCode
    /// This platform has no system browser session to present (the macOS
    /// unit-test host).
    case unsupportedPlatform
}
