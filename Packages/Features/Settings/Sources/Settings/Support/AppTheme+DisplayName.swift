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
        case .warm: String(localized: "Warm", bundle: .module)
        case .nord: String(localized: "Nord", bundle: .module)
        case .solarized: String(localized: "Solarized", bundle: .module)
        case .forest: String(localized: "Forest", bundle: .module)
        case .cyberpunk: String(localized: "Cyberpunk", bundle: .module)
        case .terminal: String(localized: "Terminal", bundle: .module)
        case .vaporwave: String(localized: "Vaporwave", bundle: .module)
        }
    }
}
