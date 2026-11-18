import Foundation

public enum ConnectionIdentityError: Error, LocalizedError, Equatable, Sendable {
    case serverChanged
    case userChanged
    case sessionChanged
    case unverifiedUser
    case userReadRequired

    public var errorDescription: String? {
        switch self {
        case .serverChanged:
            String(localized: "To use another server, add a new connection.", bundle: .module)
        case .userChanged:
            String(
                localized: "This connection belongs to another user. Use the original account or add a new connection.",
                bundle: .module,
            )
        case .sessionChanged:
            String(localized: "This connection changed while you were signing in. Try again.", bundle: .module)
        case .unverifiedUser:
            String(localized: "Couldn't verify your user. Try signing in again.", bundle: .module)
        case .userReadRequired:
            String(
                localized: "This token needs permission to read your user. Update its permissions and try again.",
                bundle: .module,
            )
        }
    }
}
