import SwiftUI
import VikuDesignSystem

/// A resolved menu description shared by SwiftUI and native presentations.
/// Handlers capture the item represented by this description, not a mutable selection.
@MainActor
public struct ContextMenuItem: Identifiable {
    public enum Content {
        case action(isSelected: Bool, isDestructive: Bool, perform: @MainActor () -> Void)
        case submenu([ContextMenuItem])
        case group([ContextMenuItem])
    }

    public let id: String
    public let title: String
    public let systemImage: String?
    public let content: Content

    public static func action(
        _ id: String, title: String, systemImage: String? = nil,
        isSelected: Bool = false, isDestructive: Bool = false,
        perform: @escaping @MainActor () -> Void,
    ) -> Self {
        Self(
            id: id,
            title: title,
            systemImage: systemImage,
            content: .action(isSelected: isSelected, isDestructive: isDestructive, perform: perform),
        )
    }

    public static func submenu(_ id: String, title: String, systemImage: String, items: [Self]) -> Self {
        Self(id: id, title: title, systemImage: systemImage, content: .submenu(items))
    }

    public static func group(_ id: String, items: [Self]) -> Self {
        Self(id: id, title: "", systemImage: nil, content: .group(items))
    }
}

/// Renders the same resolved actions in a standard SwiftUI menu, such as List's.
public struct ContextMenuItems: View {
    private let items: [ContextMenuItem]
    @Environment(\.vikuPalette) private var palette

    public init(_ items: [ContextMenuItem]) {
        self.items = items
    }

    public var body: some View {
        ForEach(items) { item in
            switch item.content {
            case let .action(isSelected, isDestructive, perform):
                Button(role: isDestructive ? .destructive : nil, action: perform) {
                    HStack {
                        Label {
                            Text(verbatim: item.title)
                        } icon: {
                            if let image = item.systemImage {
                                Image(systemName: image)
                            }
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .tint(isDestructive ? palette.semanticDanger : palette.brand)
            case let .submenu(children):
                Menu {
                    ContextMenuItems(children)
                } label: {
                    Label {
                        Text(verbatim: item.title)
                    } icon: {
                        if let image = item.systemImage {
                            Image(systemName: image)
                        }
                    }
                }
            case let .group(children):
                Section { ContextMenuItems(children) }
            }
        }
    }
}
