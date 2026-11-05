import Foundation
import VikuDesignSystem

/// Ordered catalog shared by the index and article lookup. Resource names and
/// route IDs stay stable when a title or its translation changes. Localized
/// titles and summaries come from each article's front matter.
enum DocumentationArticle: String, CaseIterable, Identifiable {
    case offlineMode = "offline-mode"
    case quickAddShortcuts = "quick-add-shortcuts"
    case pushNotifications = "push-notifications"
    case serverVersionSupport = "server-version-support"
    case numberedListSample = "numbered-list-sample"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .offlineMode: "wifi.slash"
        case .quickAddShortcuts: "number"
        case .pushNotifications: "bell"
        case .serverVersionSupport: "server.rack"
        case .numberedListSample: "list.number"
        }
    }

    /// Fixed per article so filtering, language, and appearance never change
    /// its visual identity. Uses the design system's content accent colors.
    var tint: VikuColor.AccentTint {
        switch self {
        case .offlineMode: .teal
        case .quickAddShortcuts: .purple
        case .pushNotifications: .amber
        case .serverVersionSupport: .blue
        case .numberedListSample: .purple
        }
    }
}
