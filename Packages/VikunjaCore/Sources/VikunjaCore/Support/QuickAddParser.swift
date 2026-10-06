import Foundation

/// Parses the shortcuts typed into the quick-add title, in the dialect the
/// user picked (see `QuickAddSyntax`):
///
/// - `#Compras` (Todoist) or `+Compras` (Vikunja) names a project. Quoted
///   names may contain spaces: `#"Lista del super"`.
/// - `@home` (Todoist) or `*home` (Vikunja) adds a label. Several can be used.
///   A label that does not exist yet is created when the task is saved.
/// - `p1`-`p4` (Todoist) or `!1`-`!5` (Vikunja) sets a priority.
/// - A backslash before a sigil escapes it, so `\#` stays a literal `#`.
///
/// Pure and I/O-free: `tokenize` only finds shapes in the text, and `parse`
/// resolves them against the projects the caller already has. A shortcut only
/// counts when it starts the input or follows whitespace, so `a#b` stays text.
public enum QuickAddParser {
    /// A shortcut found in the input. `range` covers the whole shortcut,
    /// sigil and quotes included, so a view can color it in place.
    public enum TokenKind: Equatable, Sendable {
        case project
        case label
        case priority
    }

    public struct Token: Equatable, Sendable {
        public let kind: TokenKind
        /// The project or label name, or the priority level digits as typed.
        public let value: String
        public let range: Range<String.Index>
    }

    /// What a token means once checked against the known projects.
    public enum Resolution: Equatable, Sendable {
        case project(Project)
        /// More than one project matches. Left in the title so the user decides.
        case ambiguousProject([Project])
        case unmatchedProject
        case priority(VikunjaTask.Priority)
        case label(Label)
        /// More than one label matches. Left in the title so the user decides.
        case ambiguousLabel([Label])
        /// No label has this name. It is created when the task is saved.
        case newLabel(String)
        /// A second token of the same kind. Only the first one applies.
        case superseded
    }

    public struct ResolvedToken: Equatable, Sendable {
        public let token: Token
        public let resolution: Resolution

        /// Whether this token is removed from the title and applied to the task.
        public var isApplied: Bool {
            switch resolution {
            case .project, .priority, .label, .newLabel: true
            case .ambiguousProject, .unmatchedProject, .ambiguousLabel, .superseded: false
            }
        }
    }

    public struct Result: Equatable, Sendable {
        /// The input with applied shortcuts removed and escapes unescaped.
        public let title: String
        public let tokens: [ResolvedToken]
        /// The project named by the first project token, when it matched exactly one project.
        public let projectID: Int?
        /// The priority named by the first priority token.
        public let priority: VikunjaTask.Priority?
        /// Existing labels named by the input, each once, in input order.
        public let labelIDs: [Int]
        /// Names of labels to create on save, each once, in input order.
        public let newLabelNames: [String]
    }

    // MARK: - Parsing

    public static func parse(
        _ input: String,
        projects: [Project],
        labels: [Label] = [],
        syntax: QuickAddSyntax,
    ) -> Result {
        let scan = scan(input, syntax: syntax)
        let resolved = resolve(scan.tokens, projects: projects, labels: labels, syntax: syntax)

        var projectID: Int?
        var priority: VikunjaTask.Priority?
        for item in resolved {
            switch item.resolution {
            case let .project(project) where projectID == nil:
                projectID = project.id
            case let .priority(value) where priority == nil:
                priority = value
            default:
                break
            }
        }

        var labelIDs: [Int] = []
        var newLabelNames: [String] = []
        for item in resolved {
            switch item.resolution {
            case let .label(label) where !labelIDs.contains(label.id):
                labelIDs.append(label.id)
            case let .newLabel(name) where !newLabelNames.contains(where: { fold($0) == fold(name) }):
                newLabelNames.append(name)
            default:
                break
            }
        }

        let applied = resolved.filter(\.isApplied).map(\.token.range)
        let title = buildTitle(input: input, escapes: scan.escapes, removing: applied)

        return Result(
            title: title,
            tokens: resolved,
            projectID: projectID,
            priority: priority,
            labelIDs: labelIDs,
            newLabelNames: newLabelNames,
        )
    }

    /// Finds shortcut shapes without looking at what they refer to.
    public static func tokenize(_ input: String, syntax: QuickAddSyntax) -> [Token] {
        scan(input, syntax: syntax).tokens
    }

    // MARK: - Scanning

    private struct Scan {
        let tokens: [Token]
        /// Ranges of escaped sigils, which become the bare sigil in the title.
        let escapes: [Range<String.Index>]
    }

    private static func scan(_ input: String, syntax: QuickAddSyntax) -> Scan {
        let characters = Array(input)
        // One entry per Character plus the end index, so any character offset
        // maps back to a String.Index.
        let indices = Array(input.indices) + [input.endIndex]
        let prefix = Array(syntax.priorityPrefix)

        var tokens: [Token] = []
        var escapes: [Range<String.Index>] = []
        var offset = 0

        while offset < characters.count {
            let character = characters[offset]

            if character == "\\", offset + 1 < characters.count,
               isSigil(characters[(offset + 1)...], syntax: syntax) {
                escapes.append(indices[offset] ..< indices[offset + 2])
                offset += 2
                continue
            }

            let startsWord = offset == 0 || characters[offset - 1].isWhitespace
            guard startsWord else {
                offset += 1
                continue
            }

            if character == syntax.projectSigil,
               let shortcut = namedToken(kind: .project, at: offset, in: characters, indices: indices) {
                tokens.append(shortcut.token)
                offset = shortcut.endOffset
            } else if character == syntax.labelSigil,
                      let shortcut = namedToken(kind: .label, at: offset, in: characters, indices: indices) {
                tokens.append(shortcut.token)
                offset = shortcut.endOffset
            } else if hasPrefix(prefix, at: offset, in: characters),
                      let shortcut = priorityToken(
                          at: offset,
                          prefixLength: prefix.count,
                          syntax: syntax,
                          in: characters,
                          indices: indices,
                      ) {
                tokens.append(shortcut.token)
                offset = shortcut.endOffset
            } else {
                offset += 1
            }
        }

        return Scan(tokens: tokens, escapes: escapes)
    }

    /// True when the text right after a backslash is a sigil this dialect uses.
    private static func isSigil(_ rest: ArraySlice<Character>, syntax: QuickAddSyntax) -> Bool {
        guard let first = rest.first else { return false }
        return first == syntax.projectSigil || first == syntax.labelSigil || first == syntax.priorityPrefix.first
    }

    private static func hasPrefix(_ prefix: [Character], at offset: Int, in characters: [Character]) -> Bool {
        guard offset + prefix.count <= characters.count else { return false }
        return Array(characters[offset ..< offset + prefix.count]) == prefix
    }

    /// Reads a project or label shortcut such as `#name`, `@name` or `#"quoted name"`.
    private static func namedToken(
        kind: TokenKind,
        at offset: Int,
        in characters: [Character],
        indices: [String.Index],
    ) -> (token: Token, endOffset: Int)? {
        let bodyStart = offset + 1
        guard bodyStart < characters.count else { return nil }

        let value: String
        let endOffset: Int
        if characters[bodyStart] == "\"" {
            guard let closing = characters[(bodyStart + 1)...].firstIndex(of: "\"") else { return nil }
            value = String(characters[(bodyStart + 1) ..< closing])
            endOffset = closing + 1
        } else {
            var end = bodyStart
            while end < characters.count, !characters[end].isWhitespace {
                end += 1
            }
            value = String(characters[bodyStart ..< end])
            endOffset = end
        }

        guard !value.trimmingCharacters(in: .whitespaces).isEmpty,
              endsShortcut(at: endOffset, in: characters) else { return nil }

        let token = Token(kind: kind, value: value, range: indices[offset] ..< indices[endOffset])
        return (token, endOffset)
    }

    /// Reads a priority shortcut such as `!3` or `p2`. Only the digits in the
    /// dialect's range count, so `pay` or `p9` stay text.
    private static func priorityToken(
        at offset: Int,
        prefixLength: Int,
        syntax: QuickAddSyntax,
        in characters: [Character],
        indices: [String.Index],
    ) -> (token: Token, endOffset: Int)? {
        let digitsStart = offset + prefixLength
        var end = digitsStart
        while end < characters.count, characters[end].isNumber {
            end += 1
        }
        guard end > digitsStart else { return nil }

        let digits = String(characters[digitsStart ..< end])
        guard let level = Int(digits), syntax.priorityLevels.contains(level),
              endsShortcut(at: end, in: characters) else { return nil }

        let token = Token(kind: .priority, value: digits, range: indices[offset] ..< indices[end])
        return (token, end)
    }

    /// A shortcut ends at the end of the input or at whitespace.
    private static func endsShortcut(at offset: Int, in characters: [Character]) -> Bool {
        offset == characters.count || characters[offset].isWhitespace
    }

    // MARK: - Resolution

    private static func resolve(
        _ tokens: [Token],
        projects: [Project],
        labels: [Label],
        syntax: QuickAddSyntax,
    ) -> [ResolvedToken] {
        var seenProject = false
        var seenPriority = false

        return tokens.map { token in
            switch token.kind {
            case .project:
                if seenProject {
                    return ResolvedToken(token: token, resolution: .superseded)
                }
                seenProject = true
                let key = fold(token.value)
                let matches = projects.filter { fold($0.title) == key }
                let resolution: Resolution = switch matches.count {
                case 0: .unmatchedProject
                case 1: .project(matches[0])
                default: .ambiguousProject(matches)
                }
                return ResolvedToken(token: token, resolution: resolution)

            case .label:
                let key = fold(token.value)
                let matches = labels.filter { fold($0.title) == key }
                let resolution: Resolution = switch matches.count {
                case 0: .newLabel(token.value)
                case 1: .label(matches[0])
                default: .ambiguousLabel(matches)
                }
                return ResolvedToken(token: token, resolution: resolution)

            case .priority:
                if seenPriority {
                    return ResolvedToken(token: token, resolution: .superseded)
                }
                seenPriority = true
                let level = Int(token.value) ?? 0
                return ResolvedToken(token: token, resolution: .priority(syntax.priority(forLevel: level)))
            }
        }
    }

    // MARK: - Title

    private static func buildTitle(
        input: String,
        escapes: [Range<String.Index>],
        removing removed: [Range<String.Index>],
    ) -> String {
        var title = ""
        var index = input.startIndex
        while index < input.endIndex {
            if let range = removed.first(where: { $0.contains(index) }) {
                index = range.upperBound
                continue
            }
            if let escape = escapes.first(where: { $0.lowerBound == index }) {
                // Drop the backslash, keep the sigil.
                title.append(input[escape].last ?? " ")
                index = escape.upperBound
                continue
            }
            title.append(input[index])
            index = input.index(after: index)
        }

        return title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Case and accent insensitive, so `#compras` finds "Compras".
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
