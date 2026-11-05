import Foundation

/// Splits an optional front matter block from the top of a Markdown document.
///
/// Intentionally minimal: one `key: value` pair per line, split at the first
/// colon, values taken literally (no quotes, nesting, or lists). Lines without a
/// colon are ignored. A leading `---` without a closing `---` is plain Markdown.
public struct MarkdownFrontMatter: Equatable, Sendable {
    /// Parsed fields, empty when the document has no front matter.
    public let fields: [String: String]
    /// The Markdown after the closing fence, exactly as stored.
    public let body: String

    public init(parsing text: String) {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.first.map(Self.isFence) == true,
              let close = lines.indices.dropFirst().first(where: { Self.isFence(lines[$0]) })
        else {
            self.fields = [:]
            self.body = text
            return
        }

        var fields: [String: String] = [:]
        for line in lines[1 ..< close] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.fields = fields
        self.body = lines.dropFirst(close + 1).first.map { String(text[$0.startIndex...]) } ?? ""
    }

    public subscript(key: String) -> String? {
        fields[key]
    }

    /// A `yyyy-MM-dd` value as midnight UTC. Format it with a UTC time zone so
    /// the displayed day matches the written one everywhere.
    public func date(for key: String) -> Date? {
        guard let value = fields[key] else { return nil }
        return try? Date(value, strategy: .iso8601.year().month().day())
    }

    /// A comma-separated value as trimmed items, without empty entries.
    public func list(for key: String) -> [String] {
        (fields[key] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func isFence(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }
}
