import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

@MainActor
struct ContextMenuSessionTests {
    @Test
    func `an open menu retains its task state checks and handlers across live updates`() throws {
        var completedIDs: [EntityID] = []
        let first = VikunjaTask(id: 1, title: "First", isDone: true, priority: .low, projectID: 1)
        let second = VikunjaTask(id: 2, title: "Second", priority: .urgent, projectID: 1)
        let session = ContextMenuSession(items(for: first) { completedIDs.append($0) })
        let visible = session.begin(.menu)

        for _ in 0 ..< 3 {
            session.update(items(for: second) { completedIDs.append($0) })
        }

        #expect(visible[0].title == "Reopen")
        #expect(session.displayed[0].title == "Reopen")
        try select(session.displayed[0])
        #expect(completedIDs == [first.id])
        #expect(try selectedPriority(session.displayed) == String(first.priority.rawValue))

        session.end(.menu)
        let reopened = session.begin(.menu)
        #expect(reopened[0].title == "Complete")
        #expect(try selectedPriority(reopened) == String(second.priority.rawValue))
        try select(reopened[0])
        #expect(completedIDs == [first.id, second.id])
    }

    @Test
    func `an edit during the priority submenu changes the next presentation only`() throws {
        let task = VikunjaTask(id: 1, title: "Task", priority: .low, projectID: 1)
        var changed = task
        changed.priority = .urgent
        let session = ContextMenuSession(items(for: task) { _ in })
        session.begin(.menu)

        session.update(items(for: changed) { _ in })

        #expect(try selectedPriority(session.displayed) == String(VikunjaTask.Priority.low.rawValue))
        session.end(.menu)
        #expect(try selectedPriority(session.begin(.menu)) == String(VikunjaTask.Priority.urgent.rawValue))
    }

    @Test(arguments: [true, false])
    func `a drag from the menu keeps the snapshot until both interactions finish`(menuEndsFirst: Bool) {
        let session = ContextMenuSession("original")
        session.begin(.menu)
        session.begin(.drag)
        session.update("updated")

        session.end(menuEndsFirst ? .menu : .drag)

        #expect(session.isPresented)
        #expect(session.displayed == "original")

        session.end(menuEndsFirst ? .drag : .menu)

        #expect(!session.isPresented)
        #expect(session.displayed == "updated")
    }

    @Test
    func `cancelled and repeated presentations release their snapshots`() {
        let session = ContextMenuSession("first")
        session.begin(.menu)
        session.update("second")
        #expect(session.begin(.menu) == "first")
        session.end(.menu)
        #expect(session.begin(.menu) == "second")
        session.end(.menu)
        session.update("third")
        #expect(session.begin(.drag) == "third")
        session.end(.drag)
        #expect(!session.isPresented)
    }

    private func items(for task: VikunjaTask, onCompletion: @escaping (EntityID) -> Void) -> [ContextMenuItem] {
        [
            .action("completion", title: task.isDone ? "Reopen" : "Complete") { onCompletion(task.id) },
            .submenu(
                "priority", title: "Priority", systemImage: "flag",
                items: VikunjaTask.Priority.selectable.map { priority in
                    .action(
                        String(priority.rawValue),
                        title: String(priority.rawValue),
                        isSelected: task.priority == priority,
                    ) {}
                },
            ),
        ]
    }

    private func select(_ item: ContextMenuItem) throws {
        guard case let .action(_, _, perform) = item.content else {
            Issue.record("Expected an action"); return
        }
        perform()
    }

    private func selectedPriority(_ items: [ContextMenuItem]) throws -> String? {
        guard case let .submenu(priorities) = try #require(items.first { $0.id == "priority" }).content else {
            Issue.record("Expected priority submenu"); return nil
        }
        return priorities.first { item in
            guard case let .action(selected, _, _) = item.content else { return false }
            return selected
        }?.id
    }
}
