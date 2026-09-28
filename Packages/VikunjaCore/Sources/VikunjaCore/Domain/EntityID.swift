import Foundation

/// Identity for an entity that may exist locally before the server has
/// assigned it a real id. Vikunja never accepts a client-supplied id, so an
/// entity created offline is `.local` until its create round-trips, then
/// becomes `.remote`.
///
/// One shared type is reused as-is across every entity (`Project`,
/// `VikunjaTask`, `Label`, ...) rather than a distinct type per entity. See
/// docs/OFFLINE_SYNC_DESIGN.md §4.2.
public enum EntityID: Hashable, Sendable {
    case local(UUID)
    case remote(Int)
}
