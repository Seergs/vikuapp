#if DEBUG
import Foundation
import VikunjaCore

/// Explicit @concurrent token closure types match Core's protocol across the
/// app target's NonisolatedNonsendingByDefault compilation setting.
nonisolated struct UITestClientFactory: InstanceClientFactoryProtocol {
    private struct Instance: Sendable {
        let tasks: UITestTaskRepository
        let projects: UITestProjectRepository
        let auxiliary = UITestAuxiliaryRepository()
        let capabilities: UITestCapabilityProvider
    }

    private let instances: [URL: Instance]
    private let unsupportedAuth = UITestAuxiliaryRepository()

    init(directory: URL, scenario: UITestScenario, resetsState: Bool) throws {
        let capabilities = UITestCapabilityProvider(
            version: scenario.version, supportsAPIV2: scenario != .capabilityLimited,
        )
        self.instances = try Dictionary(uniqueKeysWithValues: scenario.instances.enumerated().map { index, account in
            let path = directory.appendingPathComponent("instance-\(index)", isDirectory: true)
            if resetsState {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
            return try (account.baseURL, Instance(
                tasks: UITestTaskRepository(
                    directory: path, seed: resetsState ? scenario : nil, secondInstance: index == 1,
                ),
                projects: UITestProjectRepository(directory: path, seed: resetsState, secondInstance: index == 1),
                capabilities: capabilities,
            ))
        })
    }

    private func instance(for url: URL) -> Instance {
        guard let instance = instances[url] else { fatalError("No repository fixture for this UI test instance") }
        return instance
    }

    func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider {
        instances[baseURL]?.capabilities ?? UITestCapabilityProvider(version: nil, supportsAPIV2: false)
    }

    func makeAuthService(baseURL: URL) -> AuthServiceProtocol {
        instances[baseURL]?.auxiliary ?? unsupportedAuth
    }

    func makeProjectRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> ProjectRepositoryProtocol {
        instance(for: baseURL).projects
    }

    func makeTaskRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        instance(for: baseURL).tasks
    }

    func makeTaskBulkUpdateRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskBulkUpdateRepositoryProtocol {
        instance(for: baseURL).tasks
    }

    func makeLabelRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> LabelRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeTaskRelationRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeTaskAttachmentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeUserRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> UserRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeBucketRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> BucketRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeWebhookRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> WebhookRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }

    func makeFilterRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable @concurrent () async throws -> String?,
    ) -> FilterRepositoryProtocol {
        instance(for: baseURL).auxiliary
    }
}

nonisolated struct UITestCapabilityProvider: CapabilityProvider {
    let version: String?
    let supportsAPIV2: Bool

    func serverInfo() async throws -> VikunjaServerInfo {
        guard let version else { throw UITestFixtureError.unsupported("Probing an unknown instance") }
        return VikunjaServerInfo(version: version, caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        supportsAPIV2 && feature == .apiV2
    }
}
#endif
