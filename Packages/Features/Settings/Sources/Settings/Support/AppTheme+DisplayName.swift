import Foundation
import VikunjaCore

/// User-facing copy for the appearance picker, kept out of `VikunjaCore` the
/// same way `VikunjaError+DisplayMessage.swift` keeps error copy out of it.
extension AppTheme {
    var displayName: String {
        switch self {
        case .system: String(localized: "Automatic", bundle: .module)
        case .light: String(localized: "Light", bundle: .module)
        case .dark: String(localized: "Dark", bundle: .module)
        }
    }
}
