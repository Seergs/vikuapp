import VikunjaCore

/// A single visit's selection. Temporary fallback to List lasts for the visit.
struct ProjectViewPresentation {
    private(set) var mode: ProjectDisplayMode
    private(set) var boardID: Int?
    private var receivedReachability = false

    init(selection: ProjectViewSelection) {
        switch selection {
        case .list:
            self.mode = .list
        case let .kanban(boardID):
            self.mode = .kanban
            self.boardID = boardID
        }
    }

    func visibleMode(kanbanSupport: Bool?, kind: ProjectKind) -> ProjectDisplayMode? {
        guard mode == .kanban, kind != .favorites, kanbanSupport != false else { return .list }
        guard kanbanSupport == true, kind != .savedFilter || receivedReachability else { return nil }
        return .kanban
    }

    mutating func updateReachability(isOnline: Bool, kind: ProjectKind) {
        guard kind == .savedFilter else { return }
        receivedReachability = true
        if !isOnline {
            mode = .list
        }
    }

    mutating func select(_ mode: ProjectDisplayMode) -> ProjectViewSelection {
        self.mode = mode
        return mode == .list ? .list : .kanban(boardID: boardID)
    }

    mutating func selectBoard(_ id: Int) -> ProjectViewSelection {
        boardID = id
        return .kanban(boardID: id)
    }

    mutating func showListWhenNoBoards() {
        mode = .list
        boardID = nil
    }
}

enum ProjectDisplayMode: Hashable {
    case list
    case kanban
}
