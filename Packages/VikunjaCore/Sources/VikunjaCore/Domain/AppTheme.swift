/// The user's chosen color-scheme preference for the app. Purely descriptive —
/// resolving `.system` to whatever the device is currently in, and applying
/// the result as a `ColorScheme`, is a rendering concern owned by whatever
/// implements `AppThemeStoring`. Mirrors `ToastStyle`/`HapticStyle`'s role.
public enum AppTheme: String, Sendable, Equatable, CaseIterable, Codable {
    case system
    case light
    case dark
    /// A light-scheme palette with warm off-white surfaces instead of the
    /// standard cool grays, same brand accent. Forces the light scheme.
    case warm
}
