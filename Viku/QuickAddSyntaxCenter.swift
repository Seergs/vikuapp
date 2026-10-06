import Foundation
import Observation
import VikunjaCore

/// Owns the user's quick-add shortcut dialect: Todoist (`#Project`, `p1`) or
/// Vikunja (`+Project`, `!1`), or off. Off is the default: shortcuts can change
/// a title (and create labels), so they are opt-in and experimental. Reads from
/// `UserDefaults` on launch (a plain UI preference, not a credential, so
/// `UserDefaults` is the right home) and persists every change. One instance
/// lives for the whole app, created by the composition root and handed to
/// ViewModels as `QuickAddSyntaxStore`.
@Observable
@MainActor
final class QuickAddSyntaxCenter: QuickAddSyntaxStore {
    private static let key = "quickAdd.syntax"

    /// `nil` when shortcuts are off. A missing or unknown stored value means off.
    private(set) var syntax: QuickAddSyntax?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.syntax = defaults.string(forKey: Self.key).flatMap(QuickAddSyntax.init(rawValue:))
    }

    func setSyntax(_ syntax: QuickAddSyntax?) {
        self.syntax = syntax
        if let syntax {
            defaults.set(syntax.rawValue, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
