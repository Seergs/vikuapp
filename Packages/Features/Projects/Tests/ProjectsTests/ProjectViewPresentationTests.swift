@testable import Projects
import Testing
import VikunjaCore

struct ProjectViewPresentationTests {
    @Test func `project restores its board without waiting for connectivity`() {
        var view = ProjectViewPresentation(selection: .kanban(boardID: 42))
        #expect(view.visibleMode(kanbanSupport: nil, kind: .project) == nil)
        view.updateReachability(isOnline: false, kind: .project)
        #expect(view.visibleMode(kanbanSupport: true, kind: .project) == .kanban)
        #expect(view.boardID == 42)
        #expect(view.select(.list) == .list)
        #expect(view.select(.kanban) == .kanban(boardID: 42))
        #expect(view.selectBoard(7) == .kanban(boardID: 7))
    }

    @Test func `saved filter stays in List after reconnection and restores its board on the next visit`() {
        let remembered = ProjectViewSelection.kanban(boardID: 42)
        var firstVisit = ProjectViewPresentation(selection: remembered)
        #expect(firstVisit.visibleMode(kanbanSupport: true, kind: .savedFilter) == nil)
        firstVisit.updateReachability(isOnline: false, kind: .savedFilter)
        #expect(firstVisit.visibleMode(kanbanSupport: true, kind: .savedFilter) == .list)
        firstVisit.updateReachability(isOnline: true, kind: .savedFilter)
        #expect(firstVisit.visibleMode(kanbanSupport: true, kind: .savedFilter) == .list)

        var nextVisit = ProjectViewPresentation(selection: remembered)
        nextVisit.updateReachability(isOnline: true, kind: .savedFilter)
        #expect(nextVisit.visibleMode(kanbanSupport: true, kind: .savedFilter) == .kanban)
        #expect(nextVisit.boardID == 42)
    }

    @Test func `the screen shows List when Kanban is unsupported or has no boards`() {
        var view = ProjectViewPresentation(selection: .kanban(boardID: 42))
        #expect(view.visibleMode(kanbanSupport: false, kind: .project) == .list)
        #expect(view.visibleMode(kanbanSupport: true, kind: .favorites) == .list)
        view.showListWhenNoBoards()
        #expect(view.visibleMode(kanbanSupport: true, kind: .project) == .list)
        #expect(view.boardID == nil)
    }
}
