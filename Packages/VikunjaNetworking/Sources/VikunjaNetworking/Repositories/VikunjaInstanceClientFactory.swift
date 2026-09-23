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
        let client = URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider)
        return VikunjaTaskRepositorySwitch(
            v1: VikunjaTaskRepository(client: client),
            v2: VikunjaTaskRepositoryV2(client: client),
            capabilityProvider: VikunjaCapabilityProvider(client: client),
        )
    }

    public func makeLabelRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> LabelRepositoryProtocol {
        let client = URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider)
        return VikunjaLabelRepositorySwitch(
            v1: VikunjaLabelRepository(client: client),
            v2: VikunjaLabelRepositoryV2(client: client),
            capabilityProvider: VikunjaCapabilityProvider(client: client),
        )
    }

    public func makeTaskRelationRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> TaskRelationRepositoryProtocol {
        let client = URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider)
        return VikunjaTaskRelationRepositorySwitch(
            v1: VikunjaTaskRelationRepository(client: client),
            v2: VikunjaTaskRelationRepositoryV2(client: client),
            capabilityProvider: VikunjaCapabilityProvider(client: client),
        )
    }

    public func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> TaskCommentRepositoryProtocol {
        let client = URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider)
        return VikunjaTaskCommentRepositorySwitch(
            v1: VikunjaTaskCommentRepository(client: client),
            v2: VikunjaTaskCommentRepositoryV2(client: client),
            capabilityProvider: VikunjaCapabilityProvider(client: client),
        )
    }

    public func makeUserRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
    ) -> UserRepositoryProtocol {
        let client = URLSessionAPIClient(baseURL: baseURL, authTokenProvider: tokenProvider)
        return VikunjaUserRepositorySwitch(
            v1: VikunjaUserRepository(client: client),
            v2: VikunjaUserRepositoryV2(client: client),
            capabilityProvider: VikunjaCapabilityProvider(client: client),
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
