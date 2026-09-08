import VikunjaCore

/// User-facing copy for the errors a load/save can surface, shared by every
/// load state in this feature so the wording stays consistent across screens.
extension VikunjaError {
    var displayMessage: String {
        switch self {
        case .invalidInstanceURL:
            "That doesn't look like a valid instance address."
        case .insecureInstanceURL:
            "That address uses http. Turn on \"Allow insecure connection\" to connect over an unencrypted link."
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
