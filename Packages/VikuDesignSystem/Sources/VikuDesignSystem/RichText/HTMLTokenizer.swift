import Foundation

/// One lexical unit of an HTML string. `RichText` only needs a flat token
/// stream (start tag / end tag / text) rather than a full DOM, so this is a
/// deliberately small scanner: no error recovery beyond "keep going", no
/// namespace or CDATA handling, entities decoded only in text.
enum HTMLToken: Equatable {
    case startTag(name: String, attributes: [String: String], selfClosing: Bool)
    case endTag(name: String)
    case text(String)
}

enum HTMLTokenizer {
    /// HTML void elements: they never have a closing tag, so the parser must
    /// not wait for one.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    static func tokenize(_ html: String) -> [HTMLToken] {
        tokenizeWithRanges(html).map(\.token)
    }

    /// Original source spans let edits preserve markup outside the target tag.
    static func tokenizeWithRanges(_ html: String) -> [(token: HTMLToken, range: Range<String.Index>)] {
        var scanner = Scanner(html)
        let positions = Array(html.unicodeScalars.indices) + [html.endIndex]
        var tokens: [HTMLToken] = []
        var located: [(token: HTMLToken, range: Range<String.Index>)] = []

        while let scalar = scanner.current {
            let start = scanner.index
            let count = tokens.count
            if scalar != "<" {
                appendText(scanner.consumeText(), to: &tokens)
            } else if scanner.matches("<!--") {
                scanner.skipUntilPast("-->")
            } else if scanner.peek(1) == "!" || scanner.peek(1) == "?" {
                scanner.skipUntilPast(">")
            } else if scanner.peek(1) == "/" {
                appendEndTag(scanner.consumeEndTag(), to: &tokens)
            } else {
                tokens.append(makeStartTag(from: scanner.consumeStartTagBody()))
            }
            if tokens.count > count, let token = tokens.last {
                located.append((token, positions[start] ..< positions[scanner.index]))
            }
        }

        return located
    }

    private static func appendText(_ raw: String, to tokens: inout [HTMLToken]) {
        let decoded = decodeEntities(raw)
        if !decoded.isEmpty {
            tokens.append(.text(decoded))
        }
    }

    private static func appendEndTag(_ raw: String, to tokens: inout [HTMLToken]) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty {
            tokens.append(.endTag(name: name))
        }
    }

    private static func makeStartTag(from body: String) -> HTMLToken {
        var body = body
        var selfClosing = false
        if body.hasSuffix("/") {
            selfClosing = true
            body.removeLast()
        }
        let (name, attributes) = parseTag(body)
        if voidElements.contains(name) {
            selfClosing = true
        }
        return .startTag(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    /// Splits `img src="a.png" alt="x"` into a lowercased name and its
    /// attributes. Bare attributes (`disabled`) map to an empty string.
    private static func parseTag(_ body: String) -> (name: String, attributes: [String: String]) {
        var scanner = Scanner(body)
        scanner.skipWhitespace()
        let name = scanner.consumeWhile { !$0.isHTMLWhitespace }

        var attributes: [String: String] = [:]
        while true {
            scanner.skipWhitespace()
            guard scanner.current != nil else { break }
            let key = scanner.consumeWhile { !$0.isHTMLWhitespace && $0 != "=" }
            scanner.skipWhitespace()

            guard scanner.current == "=" else {
                if !key.isEmpty {
                    attributes[key.lowercased()] = ""
                }
                continue
            }
            scanner.advance() // '='
            scanner.skipWhitespace()
            if !key.isEmpty {
                attributes[key.lowercased()] = decodeEntities(scanner.consumeAttributeValue())
            }
        }

        return (name.lowercased(), attributes)
    }

    /// Decodes the named entities the editor emits plus decimal/hex numeric
    /// references. An unrecognized `&...;` is left untouched.
    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var result = ""
        var remainder = Substring(input)

        while let ampersand = remainder.firstIndex(of: "&") {
            result += remainder[remainder.startIndex ..< ampersand]
            let afterAmp = remainder.index(after: ampersand)

            guard let semicolon = remainder[afterAmp...].firstIndex(of: ";"),
                  remainder.distance(from: afterAmp, to: semicolon) <= 10
            else {
                result.append("&")
                remainder = remainder[afterAmp...]
                continue
            }

            result += decodeEntity(String(remainder[afterAmp ..< semicolon]))
            remainder = remainder[remainder.index(after: semicolon)...]
        }

        result += remainder
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"",
        "apos": "'", "nbsp": "\u{00A0}", "hellip": "\u{2026}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "copy": "\u{00A9}",
        "reg": "\u{00AE}", "trade": "\u{2122}", "times": "\u{00D7}",
    ]

    /// Resolves the text between `&` and `;`. Returns the original `&entity;`
    /// spelling when it isn't one we know.
    private static func decodeEntity(_ entity: String) -> String {
        if entity.hasPrefix("#") {
            let digits = entity.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            if let value, let scalar = Unicode.Scalar(value) {
                return String(scalar)
            }
        } else if let replacement = namedEntities[entity.lowercased()] {
            return replacement
        }
        return "&\(entity);"
    }
}

private extension Unicode.Scalar {
    var isHTMLWhitespace: Bool {
        self == " " || self == "\t" || self == "\n" || self == "\r" || self == "\u{0C}"
    }
}

/// A forward-only cursor over a string's unicode scalars, with the few
/// consume-operations the tokenizer needs.
private struct Scanner {
    private let scalars: [Unicode.Scalar]
    private(set) var index = 0

    init(_ string: String) {
        self.scalars = Array(string.unicodeScalars)
    }

    var current: Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    func peek(_ offset: Int) -> Unicode.Scalar? {
        let target = index + offset
        return target < scalars.count ? scalars[target] : nil
    }

    mutating func advance() {
        index += 1
    }

    func matches(_ literal: String) -> Bool {
        let wanted = Array(literal.unicodeScalars)
        guard index + wanted.count <= scalars.count else { return false }
        return Array(scalars[index ..< index + wanted.count]) == wanted
    }

    mutating func skipWhitespace() {
        while let scalar = current, scalar.isHTMLWhitespace {
            index += 1
        }
    }

    mutating func consumeWhile(_ predicate: (Unicode.Scalar) -> Bool) -> String {
        var result = ""
        while let scalar = current, predicate(scalar) {
            result.unicodeScalars.append(scalar)
            index += 1
        }
        return result
    }

    mutating func skipUntilPast(_ literal: String) {
        while current != nil, !matches(literal) {
            index += 1
        }
        if current != nil {
            index += literal.unicodeScalars.count
        }
    }

    /// Text up to the next `<`.
    mutating func consumeText() -> String {
        consumeWhile { $0 != "<" }
    }

    /// The name inside `</name>`, cursor left past the `>`.
    mutating func consumeEndTag() -> String {
        index += 2 // '</'
        let name = consumeWhile { $0 != ">" }
        if current != nil {
            index += 1
        } // '>'
        return name
    }

    /// Everything between `<` and the matching `>` (quotes may hold a `>`),
    /// cursor left past the `>`.
    mutating func consumeStartTagBody() -> String {
        index += 1 // '<'
        var body = ""
        var quote: Unicode.Scalar?
        while let scalar = current {
            if let active = quote {
                if scalar == active {
                    quote = nil
                }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == ">" {
                break
            }
            body.unicodeScalars.append(scalar)
            index += 1
        }
        if current != nil {
            index += 1
        } // '>'
        return body
    }

    /// A quoted or bare attribute value at the cursor.
    mutating func consumeAttributeValue() -> String {
        guard let scalar = current else { return "" }
        if scalar == "\"" || scalar == "'" {
            index += 1
            let value = consumeWhile { $0 != scalar }
            if current != nil {
                index += 1
            }
            return value
        }
        return consumeWhile { !$0.isHTMLWhitespace }
    }
}
