import Foundation
import VikunjaCore

/// Builds a `CapabilityProvider` for an instance URL the user just typed in —
/// used by the onboarding flow to validate a connection (`GET /api/v1/info`)
/// before an `InstanceAccount` exists for the composition root to wire a
/// long-lived client through.
public struct VikunjaInstanceClientFactory: InstanceClientFactoryProtocol {
    public init() {}

    public func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider {
        VikunjaCapabilityProvider(client: URLSessionAPIClient(baseURL: baseURL))
    }

    public func makeAuthService(baseURL: URL) -> AuthServiceProtocol {
        VikunjaAuthService(client: URLSessionAPIClient(baseURL: baseURL), baseURL: baseURL)
    }

    public func makeProjectRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> ProjectRepositoryProtocol {
        let client = URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider)
        return VikunjaProjectRepositorySwitch(
            v1: VikunjaProjectRepository(client: client),
            v2: VikunjaProjectRepositoryV2(client: client),
            capabilityProvider: VikunjaCapabilityProvider(client: client),
        )
    }

    public func makeTaskRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> TaskRepositoryProtocol {
        VikunjaTaskRepository(
            client: URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider),
        )
    }

    public func makeLabelRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> LabelRepositoryProtocol {
        VikunjaLabelRepository(
            client: URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider),
        )
    }

    public func makeTaskRelationRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> TaskRelationRepositoryProtocol {
        VikunjaTaskRelationRepository(
            client: URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider),
        )
    }

    public func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> TaskCommentRepositoryProtocol {
        VikunjaTaskCommentRepository(
            client: URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider),
        )
    }

    public func makeUserRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> UserRepositoryProtocol {
        VikunjaUserRepository(
            client: URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider),
        )
    }

    public func makeTaskAttachmentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        VikunjaTaskAttachmentRepository(
            client: URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider),
        )
    }
}
