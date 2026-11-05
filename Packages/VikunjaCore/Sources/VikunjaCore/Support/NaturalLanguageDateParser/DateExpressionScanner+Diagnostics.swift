import Foundation

extension DateExpressionScanner {
    func diagnostic(at index: Int) -> Match? {
        numericDate(at: index) ?? guardedConstruction(at: index) ?? vague(at: index)
    }

    private func numericDate(at index: Int) -> Match? {
        guard Int(word(index)) != nil, word(index + 1) == "/", Int(word(index + 2)) != nil else { return nil }
        var end = index + 3
        if word(end) == "/", Int(word(end + 1)) != nil {
            end += 2
        }
        return Match(end: end, outcome: .unsupported(.numericDateFormat), rules: ["R16"])
    }

    private func guardedConstruction(at index: Int) -> Match? {
        let guards: [([String], (Parser.Language, Parser.Issue))] = [
            (["cada"], (.spanish, .recurrence)), (["every"], (.english, .recurrence)),
            (["todos", "los"], (.spanish, .recurrence)), (["todas", "las"], (.spanish, .recurrence)),
            (["every", "other"], (.english, .recurrence)),
            (["no"], (.spanish, .nonAssertiveExpression)), (["not"], (.english, .nonAssertiveExpression)),
            (["quizá"], (.spanish, .nonAssertiveExpression)), (["quizás"], (.spanish, .nonAssertiveExpression)),
            (["quiza"], (.spanish, .nonAssertiveExpression)), (["quizas"], (.spanish, .nonAssertiveExpression)),
            (["maybe"], (.english, .nonAssertiveExpression)),
            (["si", "puedo"], (.spanish, .nonAssertiveExpression)),
            (["si"], (.spanish, .nonAssertiveExpression)),
            (["if", "i", "can"], (.english, .nonAssertiveExpression)),
            (["del"], (.spanish, .dateRange)), (["from"], (.english, .dateRange)),
        ]
        for (prefix, (language, issue)) in guards where context.languages.contains(language) {
            guard sequence(prefix, at: index), whitespace(between: index + prefix.count - 1, and: index + prefix.count)
            else { continue }
            let start = index + prefix.count
            var guarded: Match?
            if let expression = composed(at: start) {
                guarded = expression
            } else if issue == .recurrence {
                guarded = recurrenceTail(at: start, language: language)
            }
            guard var match = guarded else { continue }
            if issue == .dateRange {
                let connector = language == .spanish ? "al" : "to"
                if word(match.end) == connector, let tail = composed(at: match.end + 1) {
                    match.end = tail.end
                }
                match.outcome = .ambiguous(.dateRange, alternatives: [])
            } else {
                match.outcome = .unsupported(issue)
            }
            match.language = language
            match.rules += [issue == .recurrence ? "R04" : (issue == .dateRange ? "R32" : "R33")]
            return match
        }
        return nil
    }

    private func recurrenceTail(at start: Int, language: Parser.Language) -> Match? {
        let lexicon = DateExpressionLexicon(language: language)
        if lexicon.unit(word(start)) != nil {
            return Match(end: start + 1, rules: [])
        }
        // Recognize a bounded quantity before the recurring unit/weekday.
        for count in 1 ... 3 where start + count < tokens.count {
            let quantity = (start ..< start + count).map { word($0) }
            guard lexicon.number(quantity) != nil else { continue }
            if let tail = composed(at: start + count) {
                return tail
            }
            if lexicon.unit(word(start + count)) != nil {
                return Match(end: start + count + 1, rules: [])
            }
        }
        return nil
    }

    private func vague(at index: Int) -> Match? {
        let forms: [([String], Parser.Language)] = [
            (["más", "tarde"], .spanish), (["mas", "tarde"], .spanish), (["pronto"], .spanish),
            (["este", "fin", "de", "semana"], .spanish), (["a", "principios", "de", "mes"], .spanish),
            (["soon"], .english), (["later"], .english), (["this", "weekend"], .english),
            (["early", "next", "month"], .english),
        ]
        guard let form = forms.first(where: { context.languages.contains($0.1) && sequence($0.0, at: index) }) else {
            return nil
        }
        return Match(
            end: index + form.0.count, language: form.1, outcome: .unsupported(.vagueExpression), rules: ["R04"],
        )
    }
}
