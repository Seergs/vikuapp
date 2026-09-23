import VikunjaCore

/// v2 implementation of `UserRepositoryProtocol`. Reuses v1's `UserDTO` /
/// `UserMapper` rather than adding a `UserDTOV2` — verified against a real
/// instance's `/api/v2/openapi.json`: v2's `GET /user` response
/// (`UserInfoBody`) adds account facts this app doesn't model
/// (`auth_provider`, `is_admin`, `deletion_scheduled_at`, …), but `id`,
/// `username`, `name`, `email`, and the nested `settings.default_project_id`
/// all have the same name and type as v1's response.
public final class VikunjaUserRepositoryV2: UserRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchCurrentUser() async throws -> User {
        let dto: UserDTO = try await client.send(VikunjaEndpoints.currentUserV2())
        return UserMapper.toDomain(dto)
    }
}
