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
    /// Arctic, blue-gray dark palette modeled on the Nord color scheme.
    /// Forces the dark scheme.
    case nord
    /// Desaturated teal-and-base16 dark palette modeled on Solarized Dark.
    /// Forces the dark scheme.
    case solarized
    /// A light-scheme palette with sage/moss surfaces and a forest-green
    /// accent, a cozy counterpart to `warm`'s peachy cream. Forces the light
    /// scheme.
    case forest
    /// Neon magenta-and-cyan dark palette on a near-black purple canvas.
    /// Forces the dark scheme.
    case cyberpunk
    /// Phosphor-green-on-black dark palette evoking a CRT terminal. Forces
    /// the dark scheme.
    case terminal
    /// Neon pink-and-cyan dark palette on a deep indigo canvas, evoking
    /// 80s synthwave. Forces the dark scheme.
    case vaporwave
}
