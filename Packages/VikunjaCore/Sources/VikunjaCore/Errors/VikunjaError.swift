public enum VikunjaError: Error, Equatable, Sendable {
    case unauthorized
    case notFound
    case invalidInstanceURL
    /// The user entered an `http://` instance address without opting in to an
    /// insecure connection — HTTPS is required unless the "insecure connection"
    /// toggle on the connection form is turned on.
    case insecureInstanceURL
    case server(message: String, statusCode: Int)
    case decoding(String)
    case network(String)
    case unsupportedServerVersion(minimumRequired: String, actual: String)
    /// A password login was rejected because the account has TOTP enabled
    /// and no (or an incorrect) passcode was supplied — the caller should
    /// prompt for one and retry.
    case totpRequired
    /// A password/OIDC session's refresh token was itself rejected by the
    /// server — the session can't be renewed, only replaced by signing in
    /// again. Distinct from `.unauthorized`, which covers a single rejected
    /// request (e.g. a revoked API token) and doesn't imply anything about
    /// whether renewal is possible. Thrown by `PasswordSessionRefresher`
    /// instead of its usual silent fall-back-to-the-stale-token behavior.
    case sessionExpired
}
