import VikunjaCore

public final class VikunjaUserRepository: UserRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchCurrentUser() async throws -> User {
        let dto: UserDTO = try await client.send(VikunjaEndpoints.currentUser())
        return UserMapper.toDomain(dto)
    }

    public func updateDefaultProject(id: Int?) async throws -> User {
        let current: UserDTO = try await client.send(VikunjaEndpoints.currentUser())
        let settings = (current.settings ?? UserSettingsDTO()).updatingDefaultProjectId(id ?? 0)
        try await client.send(VikunjaEndpoints.updateUserSettings(dto: settings))
        // The write endpoint's response shape isn't a verified part of this
        // app's contract; re-fetching keeps this on the same trusted decode
        // path as `fetchCurrentUser()`.
        let refreshed: UserDTO = try await client.send(VikunjaEndpoints.currentUser())
        return UserMapper.toDomain(refreshed)
    }

    public func updateOverdueTasksRemindersTime(_ time: String) async throws -> User {
        let current: UserDTO = try await client.send(VikunjaEndpoints.currentUser())
        let settings = (current.settings ?? UserSettingsDTO()).updatingOverdueTasksRemindersTime(time)
        try await client.send(VikunjaEndpoints.updateUserSettings(dto: settings))
        let refreshed: UserDTO = try await client.send(VikunjaEndpoints.currentUser())
        return UserMapper.toDomain(refreshed)
    }
}
