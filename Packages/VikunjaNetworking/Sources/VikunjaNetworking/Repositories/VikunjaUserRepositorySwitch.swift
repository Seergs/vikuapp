import VikunjaCore

/// Routes each `UserRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource).
final class VikunjaUserRepositorySwitch: UserRepositoryProtocol {
    private let v1: UserRepositoryProtocol
    private let v2: UserRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: UserRepositoryProtocol, v2: UserRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    func fetchCurrentUser() async throws -> User {
        let repository = await capabilityProvider.supports(.apiV2) ? v2 : v1
        return try await repository.fetchCurrentUser()
    }
}
