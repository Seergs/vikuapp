import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct CapacityFailureMessageTests {
    @Test func `stored capacity failures preserve the destination context`() throws {
        let error = VikunjaError.bucketCapacity(column: "Por hacer", project: "Trabajo")
        let stored = StoredSyncFailure(error: error)
        let decoded = try #require(StoredSyncFailure.decode(stored.encoded))
        #expect(decoded.displayMessage == error.displayMessage)
        #expect(decoded.kind == .bucketFull)
    }

    @Test func `existing stored capacity failures remain readable without destination context`() throws {
        let json = #"{"kind":"bucketFull","detail":"bucketFull","occurredAt":0}"#
        let decoded = try #require(StoredSyncFailure.decode(json))
        #expect(decoded.displayMessage == VikunjaError.bucketFull.displayMessage)
    }
}
