import Foundation
import Testing
@testable import VikunjaCore

struct EntityIDTests {
    @Test
    func `remote ids with the same value are equal`() {
        #expect(EntityID.remote(1) == EntityID.remote(1))
    }

    @Test
    func `remote ids with different values are not equal`() {
        #expect(EntityID.remote(1) != EntityID.remote(2))
    }

    @Test
    func `local ids with the same uuid are equal`() {
        let uuid = UUID()
        #expect(EntityID.local(uuid) == EntityID.local(uuid))
    }

    @Test
    func `local ids with different uuids are not equal`() {
        #expect(EntityID.local(UUID()) != EntityID.local(UUID()))
    }

    @Test
    func `local and remote are never equal`() {
        let uuid = UUID()
        #expect(EntityID.local(uuid) != EntityID.remote(1))
    }

    @Test
    func `is usable as a dictionary key`() {
        let uuid = UUID()
        let ids: Set<EntityID> = [.local(uuid), .remote(1), .remote(1)]
        #expect(ids == [.local(uuid), .remote(1)])
    }
}
