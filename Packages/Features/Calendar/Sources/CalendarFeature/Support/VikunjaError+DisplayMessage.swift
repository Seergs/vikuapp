import VikunjaCore

/// User-facing copy for the errors a load can surface, kept per-feature so the
/// wording stays consistent within this screen even as other features phrase
/// their own.
extension VikunjaError {
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
