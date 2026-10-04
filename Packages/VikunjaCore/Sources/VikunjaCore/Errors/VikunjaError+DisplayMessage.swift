import Foundation

public extension VikunjaError {
    /// The canonical user-facing copy for each error case, shared by every
    /// screen that surfaces a `VikunjaError`. This is domain-level text about a
    /// domain error, so it lives here rather than being re-derived per feature.
    var displayMessage: String {
        switch self {
        case .invalidInstanceURL:
            String(localized: "That doesn't look like a valid instance address.", bundle: .module)
        case .insecureInstanceURL:
            String(localized: "That address uses an insecure http connection.", bundle: .module)
        case .network:
            String(localized: "Couldn't reach that server. Check the address and your connection.", bundle: .module)
        case .timeout:
            String(localized: "The request timed out. Check your connection and try again.", bundle: .module)
        case .notFound, .decoding:
            String(localized: "That address didn't respond like a Vikunja instance.", bundle: .module)
        case .unauthorized:
            String(localized: "That server rejected the request.", bundle: .module)
        case let .server(_, statusCode):
            String(localized: "The server responded with an error (\(statusCode)).", bundle: .module)
        case let .unsupportedServerVersion(minimumRequired, _):
            String(localized: "This app needs Vikunja \(minimumRequired) or newer.", bundle: .module)
        case .totpRequired:
            String(localized: "This account needs a two-factor code.", bundle: .module)
        case .sessionExpired:
            String(localized: "Your session expired. Sign in again to continue.", bundle: .module)
        }
    }
}
