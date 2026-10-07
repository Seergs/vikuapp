/// Errors `RelayPushRegistrationService` can throw, distinct from
/// `VikunjaError` — this talks to the push relay, not a Vikunja instance.
public enum PushRegistrationError: Error, Equatable, Sendable {
    /// The relay rejected the request body (its `400`).
    case invalidRequest
    /// Too many registration attempts from this client (its `429`).
    case rateLimited
    /// The response wasn't the shape this client expects.
    case invalidResponse
    /// Any other non-2xx status, carried through as-is.
    case server(statusCode: Int)
}
