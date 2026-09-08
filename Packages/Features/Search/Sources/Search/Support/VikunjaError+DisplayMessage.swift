import VikunjaCore

extension VikunjaError {
    var displayMessage: String {
        switch self {
        case let .network(message):
            message.isEmpty ? "Network error. Check your connection." : message
        case let .decoding(message):
            message.isEmpty ? "Could not process server response." : message
        case .unauthorized:
            "Authentication failed. Please sign in again."
        case .notFound:
            "Task not found."
        case .invalidInstanceURL:
            "Invalid instance URL."
        case .insecureInstanceURL:
            "That address uses an insecure http connection."
        case let .server(message, statusCode):
            message.isEmpty ? "Server error (\(statusCode))." : message
        case let .unsupportedServerVersion(minimumRequired, actual):
            "Server version \(actual) is not supported. Minimum required: \(minimumRequired)."
        case .totpRequired:
            "This account needs a two-factor code."
        }
    }
}
