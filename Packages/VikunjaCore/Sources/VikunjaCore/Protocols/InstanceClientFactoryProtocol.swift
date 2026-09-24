import Foundation

/// Builds clients for a given instance URL. Used both by the onboarding flow,
/// to test a connection (`GET /api/v1/info`) before an `InstanceAccount`
/// exists, and by the composition root, to wire an authenticated repository
/// through for an already-connected account.
public protocol InstanceClientFactoryProtocol: Sendable {
    func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider

    /// Builds a service for logging in against `baseURL` — no `tokenProvider`,
    /// since login itself is what produces the credential.
    func makeAuthService(baseURL: URL) -> AuthServiceProtocol

    /// - Parameter tokenProvider: resolves the account's bearer token per
    ///   request, so the repository never caches a token that's since been
    ///   rotated or removed.
    func makeProjectRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> ProjectRepositoryProtocol

    func makeTaskRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskRepositoryProtocol

    func makeLabelRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> LabelRepositoryProtocol

    func makeTaskRelationRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol

    func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol

    func makeTaskAttachmentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol

    func makeUserRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> UserRepositoryProtocol
}
