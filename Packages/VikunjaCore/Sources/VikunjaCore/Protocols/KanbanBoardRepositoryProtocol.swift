/// Local queries only. Synchronization is an explicit command owned by the account.
public protocol KanbanBoardRepositoryProtocol: Sendable {
    func fetchBoard(projectID: EntityID, viewID: Int) async throws -> KanbanBoardSnapshot
}
