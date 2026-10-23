import VikunjaCore

/// Routes each `FilterRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)` - see
/// `VikunjaProjectRepositorySwitch`'s doc comment for why this stays a small
/// explicit wrapper rather than a generic one.
final class VikunjaFilterRepositorySwitch: FilterRepositoryProtocol {
    private let v1: FilterRepositoryProtocol
    private let v2: FilterRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: FilterRepositoryProtocol, v2: FilterRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> FilterRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchFilter(id: Int) async throws -> SavedFilterDetail {
        try await resolve().fetchFilter(id: id)
    }

    func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail {
        try await resolve().renameFilter(id: id, title: title)
    }

    func deleteFilter(id: Int) async throws {
        try await resolve().deleteFilter(id: id)
    }
}
