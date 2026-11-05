import Foundation

/// A deliberately small authoring convention, not a general GitHub Markdown parser.
/// Alerts start at column zero after a blank line (or at the start of the document).
/// Every body line must start with `>`; use `>` alone between paragraphs.
public enum MarkdownAlertParser {
    public enum Kind: String, CaseIterable, Equatable, Sendable {
        case note = "NOTE"
        case tip = "TIP"
        case important = "IMPORTANT"
        case warning = "WARNING"
        case caution = "CAUTION"
    }

    public enum Section: Equatable, Sendable {
        case markdown(String)
        case alert(Kind, String)
    }

    public static func sections(in markdown: String) -> [Section] {
        let lines = markdown.components(separatedBy: "\n")
        var sections: [Section] = []
        var pending: [String] = []
        var fence: (character: Character, length: Int)?
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .newlines)
            if let active = fence {
                if let candidate = codeFence(line),
                   candidate.character == active.character,
                   candidate.length >= active.length,
                   candidate.suffix.trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
            } else if let opening = codeFence(line) {
                fence = (opening.character, opening.length)
            } else if index == 0 || lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let marker = quoteBody(line),
                      let kind = Kind.allCases.first(where: { marker == "[!\($0.rawValue)]" }) {
                var body: [String] = []
                var end = index + 1
                while end < lines.count,
                      let content = quoteBody(lines[end].trimmingCharacters(in: .newlines)) {
                    body.append(content)
                    end += 1
                }
                // An empty or malformed alert remains a normal Markdown quote.
                if body.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    if !pending.isEmpty {
                        sections.append(.markdown(pending.joined(separator: "\n")))
                        pending = []
                    }
                    sections.append(.alert(kind, body.joined(separator: "\n")))
                    index = end
                    continue
                }
            }
            pending.append(lines[index])
            index += 1
        }
        if !pending.isEmpty {
            sections.append(.markdown(pending.joined(separator: "\n")))
        }
        return sections
    }

    private static func quoteBody(_ line: String) -> String? {
        if line == ">" {
            return ""
        }
        guard line.hasPrefix("> ") else { return nil }
        return String(line.dropFirst(2))
    }

    private struct CodeFence {
        let character: Character
        let length: Int
        let suffix: String
    }

    private static func codeFence(_ line: String) -> CodeFence? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let trimmed = line.dropFirst(indentation)
        guard let character = trimmed.first, character == "`" || character == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        return CodeFence(character: character, length: length, suffix: String(trimmed.dropFirst(length)))
    }
}
