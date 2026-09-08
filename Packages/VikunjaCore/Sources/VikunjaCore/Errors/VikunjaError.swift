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
}
