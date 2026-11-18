import Foundation

public protocol AuthServiceProtocol: Sendable {
    /// Every successful authentication includes the real, server-verified current user.
    /// Identity lookup failures must fail authentication before any credential is persisted.
    /// For a password login, `AuthSession.token` is an opaque persisted-
    /// credential blob (not the raw JWT) — callers must only pass it through
    /// to `AccountStoreProtocol`, never parse it, exactly as they already
    /// treat an API token string.
    func login(_ credentials: LoginCredentials) async throws -> AuthSession
    func loginWithAPIToken(_ token: String) async throws -> AuthSession
    /// Exchanges an OIDC authorization code for a Vikunja session.
    /// `redirectURI` must be the exact URI used in the authorization request
    /// that produced `code` — Vikunja's backend forwards it to the
    /// provider's token endpoint, which requires an exact match. The
    /// returned `AuthSession.token` is the same opaque persisted-credential
    /// shape `login(_:)` returns; see its doc comment.
    func loginWithOIDC(provider: OIDCProvider, code: String, redirectURI: URL) async throws -> AuthSession
    func logout() async
}

public struct AuthSession: Equatable, Sendable {
    public let token: String
    public let user: User

    public init(token: String, user: User) {
        self.token = token
        self.user = user
    }
}
