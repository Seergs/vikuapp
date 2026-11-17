#if DEBUG
import Foundation
import VikunjaCore

/// Explicit @concurrent token closure types match Core's protocol across the
/// app target's NonisolatedNonsendingByDefault compilation setting.
nonisolated struct UITestClientFactory: InstanceClientFactoryProtocol {
    private let tasks = UITestTaskRepository()
    private let projects = UITestProjectRepository()
    private let auxiliary = UITestAuxiliaryRepository()

    func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider {
        UITestCapabilityProvider()
    }

    func makeAuthService(baseURL: URL) -> AuthServiceProtocol {
        auxiliary
    }

    func makeProjectRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> ProjectRepositoryProtocol {
        projects
    }

    func makeTaskRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        tasks
    }

    func makeTaskBulkUpdateRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskBulkUpdateRepositoryProtocol {
        tasks
    }

    func makeLabelRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> LabelRepositoryProtocol {
        auxiliary
    }

    func makeTaskRelationRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol {
        auxiliary
    }

    func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        auxiliary
    }

    func makeTaskAttachmentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        auxiliary
    }

    func makeUserRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> UserRepositoryProtocol {
        auxiliary
    }

    func makeBucketRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> BucketRepositoryProtocol {
        auxiliary
    }

    func makeWebhookRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> WebhookRepositoryProtocol {
        auxiliary
    }

    func makeFilterRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> FilterRepositoryProtocol {
        auxiliary
    }
}

nonisolated struct UITestCapabilityProvider: CapabilityProvider {
    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "2.4.0", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        feature == .apiV2
    }
}
#endif
