import Foundation
import VikuDesignSystem

/// Ordered catalog shared by the index and article lookup. Resource names and
/// route IDs stay stable when a title or its translation changes.
enum DocumentationArticle: String, CaseIterable, Identifiable {
    case offlineMode = "offline-mode"
    case quickAddShortcuts = "quick-add-shortcuts"
    case pushNotifications = "push-notifications"
    case serverVersionSupport = "server-version-support"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .offlineMode: String(localized: "Using Viku Offline")
        case .quickAddShortcuts: String(localized: "Quick-Add Shortcuts")
        case .pushNotifications: String(localized: "Push Notifications")
        case .serverVersionSupport: String(localized: "Server Version Support")
        }
    }

    var summary: String {
        switch self {
        case .offlineMode: String(localized: "Work offline and sync your changes later.")
        case .quickAddShortcuts: String(localized: "Set projects, labels, and priorities as you type.")
        case .pushNotifications: String(localized: "Set up notifications and understand how they work.")
        case .serverVersionSupport: String(localized: "Learn which Vikunja server versions are supported.")
        }
    }

    var systemImage: String {
        switch self {
        case .offlineMode: "wifi.slash"
        case .quickAddShortcuts: "number"
        case .pushNotifications: "bell"
        case .serverVersionSupport: "server.rack"
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
        }
    }
}
