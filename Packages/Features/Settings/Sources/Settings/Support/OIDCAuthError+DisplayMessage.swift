import VikunjaCore

/// User-facing copy for an OIDC sign-in failure. `.canceled` is deliberately
/// not handled here — callers intercept it before it reaches this, since a
/// dismissed browser session isn't really a failure.
extension OIDCAuthError {
    var displayMessage: String {
        switch self {
        case .canceled:
            "" // Handled by the caller before this is ever reached.
        case .noPresentingViewController, .presentationUnavailable, .unsupportedPlatform:
            "Couldn't open the sign-in page. Try again."
        case .missingAuthorizationCode:
            "Sign-in didn't complete. Make sure this app's redirect URI is allowed on your identity"
                + " provider, then try again."
        }
    }
}
