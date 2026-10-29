import Foundation

/// The saved filter's positive server id is distinct from the negative
/// pseudo-project id used by its local `ProjectRecord`.
struct FilterRenamePayload: Codable, Equatable, Sendable {
    var remoteID: Int
    var title: String
}

struct FilterDeletePayload: Codable, Equatable, Sendable {
    var remoteID: Int
}
