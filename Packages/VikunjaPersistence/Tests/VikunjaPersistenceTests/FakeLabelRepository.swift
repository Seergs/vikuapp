import Foundation
import VikunjaCore

final class FakeLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    var labels: [Label] = []
    var fetchError: Error?
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    private(set) var createdLabels: [Label] = []
    private(set) var updatedLabels: [Label] = []
    private(set) var deletedIDs: [Int] = []
    private(set) var fetchLabelsCallCount = 0
    private(set) var addedLabelIDs: [(labelID: EntityID, taskID: EntityID)] = []
    private(set) var removedLabelIDs: [(labelID: EntityID, taskID: EntityID)] = []
    var addLabelError: Error?
    var removeLabelError: Error?
    private var nextRemoteID = 100

    func fetchLabels() async throws -> [Label] {
        fetchLabelsCallCount += 1
        if let fetchError {
            throw fetchError
        }
        return labels
    }

    /// Mirrors `FakeProjectRepository.create` - also adds the created label
    /// to `labels`, like a real server would list it back on the very next
    /// `fetchLabels()` call.
    func create(_ label: Label) async throws -> Label {
        if let createError {
            throw createError
        }
        createdLabels.append(label)
        let remoteID = nextRemoteID
        nextRemoteID += 1
        let created = Label(id: .remote(remoteID), title: label.title, hexColor: label.hexColor)
        labels.append(created)
        return created
    }

    func update(_ label: Label) async throws -> Label {
        if let updateError {
            throw updateError
        }
        updatedLabels.append(label)
        if let index = labels.firstIndex(where: { $0.id == label.id }) {
            labels[index] = label
        }
        return label
    }

    func delete(id: EntityID) async throws {
        if let deleteError {
            throw deleteError
        }
        if let remoteID = id.remoteValue {
            deletedIDs.append(remoteID)
        }
        labels.removeAll { $0.id == id }
    }

    func addLabel(_ labelID: EntityID, toTask taskID: EntityID) async throws {
        if let addLabelError {
            throw addLabelError
        }
        addedLabelIDs.append((labelID, taskID))
    }

    func removeLabel(_ labelID: EntityID, fromTask taskID: EntityID) async throws {
        if let removeLabelError {
            throw removeLabelError
        }
        removedLabelIDs.append((labelID, taskID))
    }
}
