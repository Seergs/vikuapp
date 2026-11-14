#if os(iOS)
import SwiftUI
import UIKit

/// Owns the native menu and drag on one painted surface. A presented menu is
/// built once from a value snapshot without replacing its visible actions or
/// resetting its submenu. The underlying card always receives live updates.
///
/// Workaround for the Kanban interactions observed with SwiftUI's `.contextMenu`
/// and `.draggable`: rapid data refreshes could briefly show the wrong completion
/// action, reset an open priority submenu, or leave card fields visually stale.
/// The SwiftUI comparison branch reproduced these issues during device testing;
/// this is not a confirmed iOS framework bug. UIKit lets us keep the presented
/// menu's actions stable while continuing to update the source card independently.
/// Reconsider this adapter when a SwiftUI implementation passes the same refresh,
/// rapid-reopening, editing, and drag-from-menu scenarios. Existing List menus
/// continue to use SwiftUI and do not need this workaround.
public struct StableContextMenuCard<Content: View>: UIViewControllerRepresentable {
    private let identity: String
    private let dragValue: String
    private let cornerRadius: CGFloat
    private let items: [ContextMenuItem]
    private let content: Content
    @Environment(\.self) private var environment

    public init(
        identity: String, dragValue: String, cornerRadius: CGFloat, items: [ContextMenuItem],
        @ViewBuilder content: () -> Content,
    ) {
        self.identity = identity
        self.dragValue = dragValue
        self.cornerRadius = cornerRadius
        self.items = items
        self.content = content()
    }

    public func makeUIViewController(context: Context) -> ContextMenuCardController {
        ContextMenuCardController(snapshot: snapshot)
    }

    public func updateUIViewController(_ controller: ContextMenuCardController, context: Context) {
        controller.update(snapshot)
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize, uiViewController: ContextMenuCardController, context: Context,
    ) -> CGSize? {
        uiViewController.fittingSize(width: proposal.replacingUnspecifiedDimensions().width)
    }

    private var snapshot: ContextMenuCardController.Snapshot {
        .init(
            identity: identity, dragValue: dragValue, cornerRadius: cornerRadius, items: items,
            content: AnyView(content.environment(\.self, environment)),
        )
    }
}

@MainActor
public final class ContextMenuCardController: UIViewController,
    UIContextMenuInteractionDelegate, UIDragInteractionDelegate {
    struct Snapshot {
        let identity: String
        let dragValue: String
        let cornerRadius: CGFloat
        let items: [ContextMenuItem]
        let content: AnyView
    }

    private let hosting: UIHostingController<AnyView>
    private let session: ContextMenuSession<Snapshot>
    private var menuIdentifier: String?

    init(snapshot: Snapshot) {
        self.hosting = UIHostingController(rootView: snapshot.content)
        self.session = ContextMenuSession(snapshot)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(snapshot:)")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        hosting.view.addInteraction(UIContextMenuInteraction(delegate: self))
        let drag = UIDragInteraction(delegate: self)
        drag.isEnabled = true
        hosting.view.addInteraction(drag)
    }

    func update(_ snapshot: Snapshot) {
        session.update(snapshot)
        // Only menu actions are frozen. UIKit owns the lifted preview; holding
        // back the live source view can leave cards stale after editing sheets.
        hosting.rootView = snapshot.content
        hosting.view.invalidateIntrinsicContentSize()
        view.invalidateIntrinsicContentSize()
        view.setNeedsLayout()
    }

    func fittingSize(width: CGFloat) -> CGSize {
        hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint,
    ) -> UIContextMenuConfiguration? {
        // A new opening can begin before the previous dismissal animation ends.
        // Its snapshot must be fresh, and the old completion must not release it.
        session.end(.menu)
        let presentation = menuForPresentation()
        let identifier = "\(presentation.identity):\(UUID().uuidString)"
        menuIdentifier = identifier
        return UIContextMenuConfiguration(identifier: identifier as NSString, previewProvider: nil) { _ in
            presentation.menu
        }
    }

    func menuForPresentation() -> (identity: String, menu: UIMenu) {
        let snapshot = session.begin(.menu)
        return (snapshot.identity, Self.makeMenu(snapshot.items))
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        UITargetedPreview(view: hosting.view, parameters: previewParameters())
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        UITargetedPreview(view: hosting.view, parameters: previewParameters())
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?,
    ) {
        let identifier = configuration.identifier as? String
        if let animator {
            animator.addCompletion { [weak self] in self?.endMenu(identifier: identifier) }
        } else {
            endMenu(identifier: identifier)
        }
    }

    private func endMenu(identifier: String?) {
        guard identifier == menuIdentifier else { return }
        menuIdentifier = nil
        end(.menu)
    }

    public func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning dragSession: any UIDragSession) -> [UIDragItem] {
        // This is a request for a possible drag, not confirmation it started.
        // A menu can win the gesture without a corresponding drag-end callback.
        let snapshot = session.displayed
        return [UIDragItem(itemProvider: NSItemProvider(object: snapshot.dragValue as NSString))]
    }

    public func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin dragSession: any UIDragSession) {
        session.begin(.drag)
    }

    public func dragInteraction(
        _ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session dragSession: any UIDragSession,
    ) -> UITargetedDragPreview? {
        UITargetedDragPreview(view: hosting.view, parameters: previewParameters())
    }

    public func dragInteraction(
        _ interaction: UIDragInteraction, session dragSession: any UIDragSession, didEndWith operation: UIDropOperation,
    ) {
        end(.drag)
    }

    private func end(_ interaction: ContextMenuSession<Snapshot>.Interaction) {
        session.end(interaction)
    }

    private func previewParameters() -> UIPreviewParameters {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: hosting.view.bounds, cornerRadius: session.displayed.cornerRadius,
        )
        return parameters
    }

    private static func makeMenu(_ items: [ContextMenuItem]) -> UIMenu {
        UIMenu(children: items.map { item in
            let image = item.systemImage.flatMap(UIImage.init(systemName:))
            switch item.content {
            case let .action(isSelected, isDestructive, perform):
                return UIAction(
                    title: item.title, image: image, identifier: UIAction.Identifier(item.id),
                    attributes: isDestructive ? .destructive : [], state: isSelected ? .on : .off,
                ) { _ in perform() }
            case let .submenu(children):
                return UIMenu(
                    title: item.title,
                    image: image,
                    identifier: UIMenu.Identifier(item.id),
                    children: makeMenu(children).children,
                )
            case let .group(children):
                return UIMenu(
                    title: "",
                    identifier: UIMenu.Identifier(item.id),
                    options: .displayInline,
                    children: makeMenu(children).children,
                )
            }
        })
    }
}
#endif
