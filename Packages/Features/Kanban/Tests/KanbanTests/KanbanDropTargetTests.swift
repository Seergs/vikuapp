@testable import Kanban
import Testing

struct KanbanDropTargetTests {
    @Test func `hovering another column replaces the previous highlight`() {
        var target = KanbanDropTarget()
        target.update(isTargeted: true, bucketID: 1)
        target.update(isTargeted: true, bucketID: 2)
        #expect(target.bucketID == 2)
        // A previous destination can deliver its exit after the new entry.
        target.update(isTargeted: false, bucketID: 1)
        #expect(target.bucketID == 2)
    }

    @Test func `returning a card to its source clears every highlight`() {
        var target = KanbanDropTarget()
        target.update(isTargeted: true, bucketID: 2)
        // Finishing any drop clears the board, even if it returns to the
        // source and the view model correctly performs no mutation.
        target.reset()
        #expect(target.bucketID == nil)
        target.update(isTargeted: false, bucketID: 2)
        #expect(target.bucketID == nil)
    }

    @Test func `leaving a destination without dropping clears its highlight`() {
        var target = KanbanDropTarget()
        target.update(isTargeted: true, bucketID: 2)
        target.update(isTargeted: false, bucketID: 2)
        #expect(target.bucketID == nil)
    }

    @Test func `a finished drop does not affect the next drag`() {
        var target = KanbanDropTarget()
        target.update(isTargeted: true, bucketID: 2)
        target.reset()
        target.update(isTargeted: true, bucketID: 3)
        target.update(isTargeted: false, bucketID: 2)
        #expect(target.bucketID == 3)
        target.reset()
        #expect(target.bucketID == nil)
    }
}
