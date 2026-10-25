import Foundation

/// Identity for an entity that may exist locally before the server has
/// assigned it a real id. Vikunja never accepts a client-supplied id, so an
/// entity created offline is `.local` until its create round-trips, then
/// becomes `.remote`.
///
/// One shared type is reused as-is across every entity (`Project`,
/// `VikunjaTask`, `Label`, ...) rather than a distinct type per entity.
public enum EntityID: Hashable, Sendable {
    case local(UUID)
    case remote(Int)

    /// The server id, or `nil` for a `.local` entity that hasn't synced yet.
    public var remoteValue: Int? {
        switch self {
        case .local:
            nil
        case let .remote(id):
            id
        }
    }
}

/// A literal id always means a known server id — there's no syntax for
/// writing a `UUID` literal, so this is unambiguous.
extension EntityID: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .remote(value)
    }
}
