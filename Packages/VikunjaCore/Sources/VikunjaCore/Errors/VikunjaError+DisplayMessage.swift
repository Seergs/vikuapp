public extension VikunjaError {
    /// The canonical user-facing copy for each error case, shared by every
    /// screen that surfaces a `VikunjaError`. This is domain-level text about a
    /// domain error, so it lives here rather than being re-derived per feature.
    var displayMessage: String {
        switch self {
        case .invalidInstanceURL:
            "That doesn't look like a valid instance address."
        case .insecureInstanceURL:
            "That address uses an insecure http connection."
        case .network:
            "Couldn't reach that server. Check the address and your connection."
        case .notFound, .decoding:
            "That address didn't respond like a Vikunja instance."
        case .unauthorized:
            "That server rejected the request."
        case let .server(_, statusCode):
            "The server responded with an error (\(statusCode))."
        case let .unsupportedServerVersion(minimumRequired, _):
            "This app needs Vikunja \(minimumRequired) or newer."
        case .totpRequired:
            "This account needs a two-factor code."
        }
    }
}
