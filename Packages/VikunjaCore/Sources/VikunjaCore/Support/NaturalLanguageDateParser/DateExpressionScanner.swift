import Foundation

struct DateExpressionScanner {
    typealias Parser = NaturalLanguageDateParser

    struct Token {
        let word: String
        let range: Range<String.Index>
    }

    struct Match {
        var end: Int
        var meaning: Parser.Meaning?
        var language: Parser.Language?
        var clock: DateExpressionResolver.Clock?
        var outcome: Parser.Outcome?
        var rules: [String]
    }

    let input: String
    let context: Parser.Context
    let tokens: [Token]
    let protectedRanges: [Range<String.Index>]

    init(input: String, context: Parser.Context, protectedRanges: [Range<String.Index>]) {
        self.input = input
        self.context = context
        self.protectedRanges = protectedRanges + Self.addressRanges(in: input)
        let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}_]+|[^\s]"#)
        self.tokens = regex?.matches(in: input, range: NSRange(input.startIndex..., in: input)).compactMap {
            guard let range = Range($0.range, in: input) else { return nil }
            return Token(word: String(input[range]).lowercased(), range: range)
        } ?? []
    }

    func parse() -> Parser.Result {
        guard !context.languages.isEmpty else { return Parser.Result(expressions: []) }
        var expressions: [Parser.Expression] = []
        var index = 0
        while index < tokens.count {
            guard !isProtected(tokens[index].range), var match = diagnostic(at: index) ?? composed(at: index) else {
                index += 1
                continue
            }
            let range = tokens[index].range.lowerBound ..< tokens[match.end - 1].range.upperBound
            guard !isProtected(range) else {
                index = match.end
                continue
            }
            if match.outcome == nil, let meaning = match.meaning {
                match.outcome = DateExpressionResolver(context: context).resolve(meaning, clock: match.clock)
                match.rules += match.clock == nil ? ["R25"] : ["R24", "R30"]
            }
            expressions.append(Parser.Expression(
                range: range,
                text: String(input[range]),
                language: match.language,
                meaning: match.meaning,
                ruleIDs: match.rules,
                outcome: match.outcome ?? .incomplete,
            ))
            index = match.end
        }
        return Parser.Result(expressions: expressions)
    }

    func word(_ index: Int) -> String {
        tokens.indices.contains(index) ? tokens[index].word : ""
    }

    func sequence(_ words: [String], at index: Int) -> Bool {
        for (offset, value) in words.enumerated() {
            guard word(index + offset) == value else { return false }
            if offset > 0, !whitespace(between: index + offset - 1, and: index + offset) {
                return false
            }
        }
        return true
    }

    func whitespace(between left: Int, and right: Int) -> Bool {
        guard tokens.indices.contains(left), tokens.indices.contains(right) else { return false }
        let gap = input[tokens[left].range.upperBound ..< tokens[right].range.lowerBound]
        return !gap.isEmpty && gap.allSatisfy(\.isWhitespace)
    }

    private func isProtected(_ range: Range<String.Index>) -> Bool {
        protectedRanges.contains { $0.overlaps(range) }
    }

    private static func addressRanges(in input: String) -> [Range<String.Index>] {
        let pattern = #"(?i)(?:\b[a-z][a-z0-9+.-]*://[^\s]+|\bwww\.[^\s]+|[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}.\-]+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        return regex?.matches(in: input, range: NSRange(input.startIndex..., in: input))
            .compactMap { Range($0.range, in: input) } ?? []
    }

    func composed(at index: Int) -> Match? {
        let choices = Parser.Language.allCases.filter { context.languages.contains($0) }.compactMap { language in
            date(at: index, lexicon: DateExpressionLexicon(language: language)) ??
                time(at: index, language: language)
        }
        guard var match = choices.max(by: { $0.end < $1.end }) else { return nil }
        let peers = choices.filter { $0.end == match.end }
        if peers.contains(where: { $0.meaning != match.meaning }) {
            match.outcome = .ambiguous(.conflictingLanguages, alternatives: [])
        }
        if match.meaning != .timeOnly, match.outcome == nil,
           whitespace(between: match.end - 1, and: match.end) {
            let timeChoices = Parser.Language.allCases.filter { context.languages.contains($0) }.compactMap {
                time(at: match.end, language: $0)
            }
            if let suffix = timeChoices.max(by: { $0.end < $1.end }) {
                if let language = match.language, let suffixLanguage = suffix.language, suffixLanguage != language {
                    match.outcome = .unsupported(.mixedLanguage)
                } else {
                    match.clock = suffix.clock
                    match.outcome = suffix.outcome
                }
                match.end = suffix.end
                match.rules += ["R24", "R27", "R31"]
            }
        }
        return withZoneDiagnostic(match)
    }

    private func withZoneDiagnostic(_ source: Match) -> Match {
        var match = source
        let zones = ["utc", "gmt", "z", "cet", "cest", "pst", "pdt", "est", "edt", "cst", "cdt", "mst", "mdt"]
        let regions = [
            "africa",
            "america",
            "antarctica",
            "arctic",
            "asia",
            "atlantic",
            "australia",
            "europe",
            "indian",
            "pacific",
            "etc",
        ]
        guard whitespace(between: match.end - 1, and: match.end) else { return match }
        if zones.contains(word(match.end)) {
            match.end += 1
            // Consume an optional numeric UTC/GMT offset, rather than parsing it again.
            if ["+", "-"].contains(word(match.end)), Int(word(match.end + 1)) != nil {
                match.end += 2
                if word(match.end) == ":", Int(word(match.end + 1)) != nil {
                    match.end += 2
                }
            }
        } else if regions.contains(word(match.end)), word(match.end + 1) == "/", !word(match.end + 2).isEmpty {
            match.end += 3
        } else {
            return match
        }
        match.outcome = .unsupported(.writtenTimeZone)
        match.rules += ["R29"]
        return match
    }
}
