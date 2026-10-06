/// The shortcut dialect the quick-add title is parsed with. A user picks one
/// in Settings. The two differ only in their symbols, so the parser is the
/// same for both.
public enum QuickAddSyntax: String, CaseIterable, Sendable {
    /// `#Project` and `p1` through `p4`, as in Todoist.
    case todoist
    /// `+Project` and `!1` through `!5`, as in Vikunja's own add magic.
    case vikunja

    /// The character that starts a project shortcut.
    public var projectSigil: Character {
        switch self {
        case .todoist: "#"
        case .vikunja: "+"
        }
    }

    /// The text that starts a priority shortcut, followed by a level digit.
    public var priorityPrefix: String {
        switch self {
        case .todoist: "p"
        case .vikunja: "!"
        }
    }

    /// The level digits this dialect accepts. Todoist has four levels, Vikunja five.
    public var priorityLevels: ClosedRange<Int> {
        switch self {
        case .todoist: 1 ... 4
        case .vikunja: 1 ... 5
        }
    }

    /// Maps a typed level onto Vikunja's priorities. Todoist's `p1` is the
    /// most urgent level, so it maps to `.urgent`, and `p4` (no priority in
    /// Todoist) maps to `.low`.
    public func priority(forLevel level: Int) -> VikunjaTask.Priority {
        switch self {
        case .todoist:
            switch level {
            case 1: .urgent
            case 2: .high
            case 3: .medium
            default: .low
            }
        case .vikunja:
            switch level {
            case 1: .low
            case 2: .medium
            case 3: .high
            case 4: .urgent
            default: .doNow
            }
        }
    }
}
