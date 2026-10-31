import Foundation

public extension RichText {
    /// Changes only the selected item's state attributes, keeping the rest of
    /// the original HTML verbatim. The token index must come from `parse(html)`.
    static func togglingTaskItem(at tokenIndex: Int, in html: String) -> String? {
        let tokens = HTMLTokenizer.tokenizeWithRanges(html)
        guard tokens.indices.contains(tokenIndex),
              case let .startTag("li", attributes, _) = tokens[tokenIndex].token
        else { return nil }

        let checked = attributes["data-checked"] != "true"
        var edits: [(Range<String.Index>, String)] = []
        let itemRange = tokens[tokenIndex].range
        let itemTag = settingAttribute("data-checked", to: checked ? "true" : "false", in: String(html[itemRange]))
        edits.append((itemRange, itemTag))

        // Only inputs belonging to this item, never a nested task's checkbox.
        var depth = 1
        for token in tokens.dropFirst(tokenIndex + 1) {
            if case .endTag("li") = token.token {
                depth -= 1
                if depth == 0 {
                    break
                }
            } else if case .startTag("li", _, _) = token.token {
                depth += 1
            } else if depth == 1,
                      case let .startTag("input", attributes, _) = token.token,
                      attributes["type"]?.lowercased() == "checkbox" {
                let inputTag = settingAttribute("checked", to: checked ? "" : nil, in: String(html[token.range]))
                edits.append((token.range, inputTag))
            }
        }

        var result = html
        for (range, replacement) in edits.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}

/// Matches whole attributes, including quoted values containing spaces or `>`.
/// Scanning every attribute avoids mistaking text inside a value for an attribute.
private func settingAttribute(_ name: String, to value: String?, in tag: String) -> String {
    let pattern = #"([^\s=<>/]+)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return tag }
    let matches = regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)).dropFirst()
    var result = tag
    let replacement = value.map { $0.isEmpty ? name : "\(name)=\"\($0)\"" } ?? ""
    var found = false
    for match in matches.reversed() {
        guard let keyRange = Range(match.range(at: 1), in: tag),
              tag[keyRange].lowercased() == name,
              let range = Range(match.range, in: tag)
        else { continue }
        result.replaceSubrange(range, with: replacement)
        found = true
    }
    if !found, value != nil, let end = result.lastIndex(of: ">") {
        let insertion = result[..<end].last == "/" ? result.index(before: end) : end
        let separator = result[..<insertion].last?.isWhitespace == true ? "" : " "
        result.insert(contentsOf: separator + replacement, at: insertion)
    }
    return result
}
