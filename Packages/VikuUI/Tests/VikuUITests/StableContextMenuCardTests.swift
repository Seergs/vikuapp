#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import VikuUI

@MainActor
struct StableContextMenuCardTests {
    @Test(arguments: [UIDropOperation.cancel, .move])
    func `an actual drag preserves action identity without blocking live card updates`(operation: UIDropOperation) throws {
        let controller = ContextMenuCardController(snapshot: snapshot(done: true, height: 40) {})
        controller.loadViewIfNeeded()
        let menu = UIContextMenuInteraction(delegate: controller)
        let configuration = try #require(
            controller.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero),
        )
        let drag = UIDragInteraction(delegate: controller)
        let dragSession = TestDragSession()
        _ = controller.dragInteraction(drag, itemsForBeginning: dragSession)
        controller.dragInteraction(drag, sessionWillBegin: dragSession)

        controller.update(snapshot(done: false, height: 80) {})
        controller.contextMenuInteraction(menu, willEndFor: configuration, animator: nil)

        #expect(controller.fittingSize(width: 284).height == 80)
        #expect(controller.menuForPresentation().identity == "done")

        controller.dragInteraction(drag, session: dragSession, didEndWith: operation)
        _ = controller.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero)
        #expect(controller.menuForPresentation().identity == "open")
    }

    @Test
    func `a tentative drag that never starts cannot leave the card or next menu stale`() throws {
        let controller = ContextMenuCardController(snapshot: snapshot(done: true, height: 40) {})
        controller.loadViewIfNeeded()
        let drag = UIDragInteraction(delegate: controller)
        let dragSession = TestDragSession()
        let items = controller.dragInteraction(drag, itemsForBeginning: dragSession)
        #expect(items.count == 1)
        #expect(items.first?.itemProvider.canLoadObject(ofClass: NSString.self) == true)
        let menu = UIContextMenuInteraction(delegate: controller)
        let configuration = try #require(
            controller.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero),
        )

        controller.update(snapshot(done: false, height: 80) {})
        controller.contextMenuInteraction(menu, willEndFor: configuration, animator: nil)

        // UIKit asked for possible drag items, but never began a drag session.
        // There is no drag-end callback to wait for in this interaction.
        #expect(controller.fittingSize(width: 284).height == 80)
        _ = controller.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero)
        #expect(controller.menuForPresentation().identity == "open")
        #expect(try checkedPriority(controller.menuForPresentation().menu) == "urgent")
    }

    @Test
    func `quick reopening uses fresh state and ignores the previous dismissal completion`() throws {
        let controller = ContextMenuCardController(snapshot: snapshot(done: true, height: 40) {})
        controller.loadViewIfNeeded()
        let interaction = UIContextMenuInteraction(delegate: controller)
        let first = try #require(
            controller.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero),
        )
        let animator = DeferredMenuAnimator()
        controller.contextMenuInteraction(interaction, willEndFor: first, animator: animator)
        controller.update(snapshot(done: false, height: 80) {})

        let second = try #require(
            controller.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero),
        )
        #expect(controller.menuForPresentation().identity == "open")
        #expect(try checkedPriority(controller.menuForPresentation().menu) == "urgent")
        controller.update(snapshot(done: true, height: 40) {})

        animator.finish()

        #expect(controller.menuForPresentation().identity == "open")
        #expect(try checkedPriority(controller.menuForPresentation().menu) == "urgent")
        controller.contextMenuInteraction(interaction, willEndFor: second, animator: nil)
        #expect(controller.menuForPresentation().identity == "done")
    }

    @Test
    func `native menu stays stable while the card renders live changes and reopens with latest values`() throws {
        var commands: [String] = []
        let initial = snapshot(done: true, height: 40) { commands.append("first") }
        let controller = ContextMenuCardController(snapshot: initial)
        controller.loadViewIfNeeded()
        let interaction = UIContextMenuInteraction(delegate: controller)
        let configuration = try #require(
            controller.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero),
        )
        let first = controller.menuForPresentation()
        let initialHeight = controller.fittingSize(width: 284).height
        let originalAction = try #require(first.menu.children.first as? UIAction)
        #expect(originalAction.title == "Reopen")
        #expect(try checkedPriority(first.menu) == "low")

        controller.update(snapshot(done: false, height: 80) { commands.append("second") })

        #expect(controller.menuForPresentation().identity == "done")
        #expect(try checkedPriority(controller.menuForPresentation().menu) == "low")
        #expect(controller.fittingSize(width: 284).height > initialHeight)
        let button = UIButton(primaryAction: originalAction)
        button.sendActions(for: .touchUpInside)
        #expect(commands == ["first"])

        controller.contextMenuInteraction(interaction, willEndFor: configuration, animator: nil)

        let next = controller.menuForPresentation()
        #expect(next.identity == "open")
        #expect(try #require(next.menu.children.first as? UIAction).title == "Complete")
        #expect(try checkedPriority(next.menu) == "urgent")
        #expect(controller.fittingSize(width: 284).height > initialHeight)
    }

    @Test
    func `native controller installs menu and drag interactions on the same painted surface`() throws {
        let controller = ContextMenuCardController(snapshot: snapshot(done: true, height: 40) {})
        controller.loadViewIfNeeded()
        let interactions = try #require(controller.children.first?.view.interactions)
        #expect(interactions.contains { $0 is UIContextMenuInteraction })
        #expect(interactions.contains { $0 is UIDragInteraction })
        let menu = controller.menuForPresentation()
        #expect(menu.identity == "done")
        // The menu uses native actions, including a real selected-state submenu.
        #expect(try checkedPriority(menu.menu) == "low")
    }

    private func snapshot(done: Bool, height: CGFloat, perform: @escaping @MainActor () -> Void)
        -> ContextMenuCardController.Snapshot {
        .init(
            identity: done ? "done" : "open", dragValue: "remote:42", cornerRadius: 12,
            items: [
                .action("completion", title: done ? "Reopen" : "Complete", perform: perform),
                .submenu("priority", title: "Priority", systemImage: "flag", items: [
                    .action("low", title: "Low", isSelected: done) {},
                    .action("urgent", title: "Urgent", isSelected: !done) {},
                ]),
            ],
            content: AnyView(Color.clear.frame(height: height)),
        )
    }

    private func checkedPriority(_ menu: UIMenu) throws -> String? {
        let submenu = try #require(menu.children.last as? UIMenu)
        return submenu.children.compactMap { $0 as? UIAction }.first { $0.state == .on }?.identifier.rawValue
    }
}

@MainActor
private final class TestDragSession: NSObject, UIDragSession {
    var items: [UIDragItem] = []
    var localContext: Any?
    var allowsMoveOperation: Bool {
        true
    }

    var isRestrictedToDraggingApplication: Bool {
        true
    }

    func location(in view: UIView) -> CGPoint {
        .zero
    }

    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool {
        false
    }

    func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool {
        false
    }
}

@MainActor
private final class DeferredMenuAnimator: NSObject, UIContextMenuInteractionAnimating {
    var previewViewController: UIViewController? {
        nil
    }

    private var completions: [() -> Void] = []

    func addAnimations(_ animations: @escaping () -> Void) {
        animations()
    }

    func addCompletion(_ completion: @escaping () -> Void) {
        completions.append(completion)
    }

    func finish() {
        for completion in completions {
            completion()
        }
        completions.removeAll()
    }
}
#endif
