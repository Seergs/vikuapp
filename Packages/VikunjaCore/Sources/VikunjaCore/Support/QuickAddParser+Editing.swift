import Foundation

/// Writes picker choices back into the quick-add text, so the text always
/// shows what will be saved. Each edit replaces the first shortcut of its kind,
/// appends one when there is none, and removes it when the choice is cleared.
public extension QuickAddParser {
    /// Returns `input` with its project shortcut set to `title`, or without it when `title` is `nil`.
    static func settingProject(_ title: String?, in input: String, syntax: QuickAddSyntax) -> String {
        let replacement = title.map { name -> String in
            // A name with spaces needs quotes to be read back as one token.
            let needsQuotes = name.contains(where: \.isWhitespace)
            let body = needsQuotes ? "\"\(name)\"" : name
            return "\(syntax.projectSigil)\(body)"
        }
        return replacingFirstToken(of: .project, in: input, syntax: syntax, with: replacement)
    }

    /// Returns `input` with its priority shortcut set to `priority`, or without it when `priority` is `.unset`.
    static func settingPriority(
        _ priority: VikunjaTask.Priority,
        in input: String,
        syntax: QuickAddSyntax,
    ) -> String {
        let replacement = syntax.level(for: priority).map { "\(syntax.priorityPrefix)\($0)" }
        return replacingFirstToken(of: .priority, in: input, syntax: syntax, with: replacement)
    }

    private static func replacingFirstToken(
        of kind: TokenKind,
        in input: String,
        syntax: QuickAddSyntax,
        with replacement: String?,
    ) -> String {
        guard let token = tokenize(input, syntax: syntax).first(where: { $0.kind == kind }) else {
            guard let replacement else { return input }
            let trimmed = input.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? replacement : "\(trimmed) \(replacement)"
        }

        var result = input
        guard let replacement else {
            // Remove the shortcut along with the space that separates it from the text before it.
            var range = token.range
            if range.lowerBound > input.startIndex,
               input[input.index(before: range.lowerBound)].isWhitespace {
                range = input.index(before: range.lowerBound) ..< range.upperBound
            }
            result.removeSubrange(range)
            return result
        }
        result.replaceSubrange(token.range, with: replacement)
        return result
    }
}
