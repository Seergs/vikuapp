import Observation
import SwiftUI
import VikunjaCore

/// Owns the user's theme preference: reads it from `UserDefaults` on launch
/// (a plain UI preference, not a credential, so `UserDefaults` — not the
/// Keychain — is the right home) and persists every change. One instance
/// lives for the whole app — created once by the composition root — and is
/// handed to `Features/Settings` as `AppThemeStoring` so it never imports this
/// package, and read directly here (as the concrete type) by `RootView` to
/// drive `.preferredColorScheme(_:)`, the same split `ToastCenter`/
/// `ToastHostModifier` use for toasts.
@Observable
@MainActor
public final class ThemeCenter: AppThemeStoring {
    private static let defaultsKey = "appTheme"

    public private(set) var theme: AppTheme

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.defaultsKey), let stored = AppTheme(rawValue: raw) {
            self.theme = stored
        } else {
            self.theme = .system
        }
    }

    public func setTheme(_ theme: AppTheme) {
        self.theme = theme
        defaults.set(theme.rawValue, forKey: Self.defaultsKey)
    }

    /// The value to hand `.preferredColorScheme(_:)`: `nil` lets the view
    /// hierarchy follow the system setting, matching `.system`. Every other
    /// theme pins its own scheme, since each has a literal (non-adaptive)
    /// palette: `.warm`/`.forest` are light-scheme variants, the rest are
    /// dark-scheme variants.
    public var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        case .warm, .forest: .light
        case .nord, .solarized, .cyberpunk, .terminal, .vaporwave: .dark
        }
    }

    /// The value to hand `@Environment(\.vikuPalette)`.
    public var palette: VikuPalette {
        switch theme {
        case .system, .light, .dark: .standard
        case .warm: .warm
        case .nord: .nord
        case .solarized: .solarized
        case .forest: .forest
        case .cyberpunk: .cyberpunk
        case .terminal: .terminal
        case .vaporwave: .vaporwave
        }
    }
}
