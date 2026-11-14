import Foundation
import VikunjaCore

final class FakeTaskRelationRepository: TaskRelationRepositoryProtocol, @unchecked Sendable {
    struct RecordedRelation: Sendable, Equatable {
        let kind: RelationKind
        let otherTaskID: EntityID
        let taskID: EntityID
    }

    private(set) var addedRelations: [RecordedRelation] = []
    private(set) var removedRelations: [RecordedRelation] = []
    var beforeAddResponse: (@Sendable () async throws -> Void)?
    var addRelationError: Error?
    var removeRelationError: Error?

    func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws {
        if let addRelationError {
            throw addRelationError
        }
        addedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
        try await beforeAddResponse?()
    }

    func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws {
        if let removeRelationError {
            throw removeRelationError
        }
        removedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }
}
