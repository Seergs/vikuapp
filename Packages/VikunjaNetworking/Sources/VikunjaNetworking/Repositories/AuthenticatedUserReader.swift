import Foundation
import VikunjaCore

enum AuthenticatedUserReader {
    /// Uses only the candidate bearer; no saved account or shared token provider is involved.
    static func fetch(client: APIClient, token: String, v2: Bool) async throws -> User {
        let route = v2 ? VikunjaEndpoints.currentUserV2() : VikunjaEndpoints.currentUser()
        let endpoint = Endpoint(path: route.path, additionalHeaders: ["Authorization": "Bearer \(token)"])
        do {
            let dto: UserDTO = try await client.send(endpoint)
            guard dto.id > 0 else { throw ConnectionIdentityError.unverifiedUser }
            try Task.checkCancellation()
            return UserMapper.toDomain(dto)
        } catch VikunjaError.server(_, 403) {
            throw VikunjaError.server(
                message: ConnectionIdentityError.userReadRequired.localizedDescription, statusCode: 403,
            )
        }
    }
}
