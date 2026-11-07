import Foundation

/// Produces a read-only query with project and label names. The original query
/// remains the source of truth for persistence and API requests.
public enum FilterQueryFormatter {
    /// Semantic text runs let the UI style resolved names without searching
    /// for their text elsewhere in the query or interpreting it as Markdown.
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let isResolvedName: Bool
    }

    public static func displayQuery(
        _ query: String,
        labelTitle: (Int) -> String?,
        projectTitle: (Int) -> String?,
    ) -> String {
        displaySegments(query, labelTitle: labelTitle, projectTitle: projectTitle).map(\.text).joined()
    }

    public static func displaySegments(
        _ query: String,
        labelTitle: (Int) -> String?,
        projectTitle: (Int) -> String?,
    ) -> [Segment] {
        let tokens = tokenize(query)
        var replacements: [(Range<String.Index>, String)] = []
        var clause: [Token] = []

        func resolveClause() {
            guard clause.count >= 3 else { return }
            let field = clause[0].text.lowercased()
            guard field == "project" || field == "labels" else { return }

            var valueStart = 2
            let multiple: Bool
            switch clause[1].text.lowercased() {
            case "=", "!=": multiple = false
            case "in", "?=", "?!=": multiple = true
            case "not" where clause.count >= 4 && clause[2].text.lowercased() == "in":
                multiple = true
                valueStart = 3
            default: return
            }

            let values = Array(clause.dropFirst(valueStart))
            guard !values.isEmpty, values.count % 2 == 1,
                  multiple || values.count == 1 else { return }
            // Validate the whole value list before making any substitutions.
            // Unknown syntax and non-ID values must remain untouched.
            for (index, token) in values.enumerated() {
                if index.isMultiple(of: 2) {
                    guard token.id != nil else { return }
                } else if token.text != "," {
                    return
                }
            }
            for token in values where token.id != nil {
                if let id = token.id,
                   let title = field == "project" ? projectTitle(id) : labelTitle(id), !title.isEmpty {
                    replacements.append((token.range, quotedIfNeeded(title)))
                }
            }
        }

        for token in tokens {
            if ["&&", "||", "(", ")"].contains(token.text) {
                resolveClause()
                clause.removeAll(keepingCapacity: true)
            } else {
                clause.append(token)
            }
        }
        resolveClause()

        // Assemble from the original slices so replacements cannot affect later
        // matches, including names that themselves contain query syntax.
        var result: [Segment] = []
        var position = query.startIndex
        for (range, title) in replacements {
            if position < range.lowerBound {
                result.append(Segment(text: String(query[position ..< range.lowerBound]), isResolvedName: false))
            }
            result.append(Segment(text: title, isResolvedName: true))
            position = range.upperBound
        }
        if position < query.endIndex {
            result.append(Segment(text: String(query[position...]), isResolvedName: false))
        }
        return result
    }

    private struct Token {
        let text: String
        let range: Range<String.Index>

        var id: Int? {
            let hasQuotes = text.first == "\"" || text.first == "'"
            let value: Substring = if hasQuotes, text.count >= 2, text.last == text.first {
                text.dropFirst().dropLast()
            } else {
                text[...]
            }
            let digits = value.first == "-" ? value.dropFirst() : value
            guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return Int(value)
        }
    }

    /// Quoted strings are opaque, including escaped quotes and logical operators.
    /// Whitespace is skipped here but retained in the original source slices.
    private static func tokenize(_ query: String) -> [Token] {
        var tokens: [Token] = []
        var cursor = query.startIndex
        let punctuation = "()&|,=!<>?\"'"
        while cursor < query.endIndex {
            let character = query[cursor]
            if character.isWhitespace {
                cursor = query.index(after: cursor)
                continue
            }
            let start = cursor
            cursor = query.index(after: cursor)
            if character == "\"" || character == "'" {
                while cursor < query.endIndex {
                    let current = query[cursor]
                    cursor = query.index(after: cursor)
                    if current == "\\", cursor < query.endIndex {
                        cursor = query.index(after: cursor)
                    } else if current == character {
                        break
                    }
                }
            } else if "&|=!<>?".contains(character) {
                while cursor < query.endIndex, "&|=!<>?".contains(query[cursor]) {
                    cursor = query.index(after: cursor)
                }
            } else if !punctuation.contains(character) {
                while cursor < query.endIndex,
                      !query[cursor].isWhitespace, !punctuation.contains(query[cursor]) {
                    cursor = query.index(after: cursor)
                }
            }
            tokens.append(Token(text: String(query[start ..< cursor]), range: start ..< cursor))
        }
        return tokens
    }

    private static func quotedIfNeeded(_ title: String) -> String {
        if title.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
            return title
        }
        let escaped = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
