import Foundation

extension DateExpressionScanner {
    func date(at index: Int, lexicon: DateExpressionLexicon) -> Match? {
        isoDate(at: index) ?? relative(at: index, lexicon: lexicon) ??
            relativeDay(at: index, lexicon: lexicon) ?? weekday(at: index, lexicon: lexicon) ??
            writtenDate(at: index, lexicon: lexicon)
    }

    private func isoDate(at index: Int) -> Match? {
        guard word(index).count >= 4, word(index).allSatisfy(\.isNumber),
              word(index + 1) == "-", let month = Int(word(index + 2)),
              word(index + 3) == "-", let day = Int(word(index + 4)),
              word(index + 2).count == 2, word(index + 4).count == 2 else { return nil }
        let source = input[tokens[index].range.lowerBound ..< tokens[index + 4].range.upperBound]
        guard !source.contains(where: \.isWhitespace) else { return nil }
        guard let year = Int(word(index)) else {
            return Match(end: index + 5, outcome: .invalid(.outOfRange), rules: ["R23"])
        }
        return Match(end: index + 5, meaning: .calendarDate(year: year, month: month, day: day), rules: ["R16", "R17"])
    }

    private func relativeDay(at index: Int, lexicon: DateExpressionLexicon) -> Match? {
        let forms: [([String], Int)] = lexicon.language == .spanish ?
            [(["pasado", "mañana"], 2), (["pasado", "manana"], 2), (["mañana"], 1), (["manana"], 1), (["hoy"], 0)] :
            [(["day", "after", "tomorrow"], 2), (["tomorrow"], 1), (["today"], 0)]
        guard let form = forms.first(where: { sequence($0.0, at: index) }) else { return nil }
        return Match(
            end: index + form.0.count, meaning: .relative(amount: form.1, unit: .day),
            language: lexicon.language, rules: ["R09"],
        )
    }

    private func weekday(at index: Int, lexicon: DateExpressionLexicon) -> Match? {
        var cursor = index
        var selection = Parser.WeekdaySelection.includingToday
        var rule = "R10"
        if ["el", "on", "este", "this", "próximo", "proximo", "next"].contains(word(cursor)) {
            let prefix = word(cursor)
            let allowed = lexicon.language == .spanish ? ["el", "este", "próximo", "proximo"] : ["on", "this", "next"]
            guard allowed.contains(prefix), whitespace(between: cursor, and: cursor + 1) else { return nil }
            cursor += 1
            if ["este", "this"].contains(prefix) {
                selection = .currentWeek; rule = "R12"
            }
            if ["próximo", "proximo", "next"].contains(prefix) {
                selection = .strictlyFuture; rule = "R11"
            }
        }
        guard let weekday = lexicon.weekday(word(cursor)) else { return nil }
        cursor += 1
        if lexicon.language == .spanish, sequence(["que", "viene"], at: cursor),
           whitespace(between: cursor - 1, and: cursor) {
            cursor += 2
            selection = .strictlyFuture
            rule = "R11"
        }
        return Match(
            end: cursor, meaning: .weekday(weekday, selection: selection),
            language: lexicon.language, rules: [rule, "R13"],
        )
    }

    private func relative(at index: Int, lexicon: DateExpressionLexicon) -> Match? {
        guard word(index) == (lexicon.language == .spanish ? "en" : "in"),
              whitespace(between: index, and: index + 1) else { return nil }
        let start = index + 1
        let other = DateExpressionLexicon(language: lexicon.language == .spanish ? .english : .spanish)
        let unitIndex = quantityEnd(at: start, lexicon: lexicon, other: other)
        guard let unitIndex,
              let unit = lexicon.unit(word(unitIndex)) else {
            if let unitIndex, other.unit(word(unitIndex)) != nil {
                return Match(
                    end: unitIndex + 1, language: lexicon.language,
                    outcome: .unsupported(.mixedLanguage), rules: ["R34"],
                )
            }
            if lexicon.number([word(start)]) != nil {
                return Match(end: start + 1, language: lexicon.language, outcome: .incomplete, rules: ["R39"])
            }
            return nil
        }
        let numberWords = (start ..< unitIndex).map { word($0) }
        let amount = lexicon.number(numberWords)
        var match = Match(
            end: unitIndex + 1, language: lexicon.language,
            rules: ["R18", "R19", "R23"] + (unit == .week ? ["R20"] : []) +
                ([.month, .year].contains(unit) ? ["R21", "R22"] : []),
        )
        guard let amount else {
            if other.number(numberWords) != nil {
                match.outcome = .unsupported(.mixedLanguage)
            } else if numberWords.count == 1, numberWords[0].allSatisfy(\.isNumber) {
                match.outcome = .invalid(.outOfRange)
            } else {
                match.outcome = .unsupported(.unsupportedQuantity)
            }
            return match
        }
        match.meaning = .relative(amount: amount, unit: unit)
        let conjunction = lexicon.language == .spanish ? "y" : "and"
        if word(match.end) == conjunction {
            let tailStart = match.end + 1
            let tailLimit = min(tokens.count, tailStart + 5)
            if let tailUnit = (tailStart ..< tailLimit).first(where: { lexicon.unit(word($0)) != nil }) {
                match.end = tailUnit + 1
                match.outcome = .unsupported(.compoundOffset)
            }
        }
        return match
    }

    private func quantityEnd(
        at start: Int, lexicon: DateExpressionLexicon, other: DateExpressionLexicon,
    ) -> Int? {
        let extra = [
            "-",
            "+",
            ".",
            "y",
            "and",
            "cuarenta",
            "cincuenta",
            "sesenta",
            "setenta",
            "ochenta",
            "noventa",
            "cien",
            "ciento",
            "mil",
            "forty",
            "fifty",
            "sixty",
            "seventy",
            "eighty",
            "ninety",
            "hundred",
            "thousand",
        ]
        for index in start ..< min(tokens.count, start + 8) {
            let value = word(index)
            if lexicon.unit(value) != nil || other.unit(value) != nil {
                return index
            }
            guard value.allSatisfy(\.isNumber) || lexicon.number([value]) != nil ||
                other.number([value]) != nil || extra.contains(value) else { return nil }
        }
        return nil
    }

    private func writtenDate(at index: Int, lexicon: DateExpressionLexicon) -> Match? {
        var cursor = index
        let day: Int
        let month: Int
        if lexicon.language == .spanish {
            guard let value = Int(word(cursor)), word(cursor + 1) == "de",
                  let monthValue = lexicon.month(word(cursor + 2)),
                  sequence([word(cursor), "de", word(cursor + 2)], at: cursor) else { return nil }
            day = value
            month = monthValue
            cursor += 3
        } else {
            guard let monthValue = lexicon.month(word(cursor)), let value = Int(word(cursor + 1)),
                  whitespace(between: cursor, and: cursor + 1) else { return nil }
            day = value
            month = monthValue
            cursor += 2
        }
        var year: Int?
        if word(cursor) == (lexicon.language == .spanish ? "de" : ",") {
            if let value = Int(word(cursor + 1)) {
                year = value; cursor += 2
            } else if !word(cursor + 1).isEmpty, word(cursor + 1).allSatisfy(\.isNumber) {
                return Match(
                    end: cursor + 2, language: lexicon.language, outcome: .invalid(.outOfRange), rules: ["R23"],
                )
            } else if lexicon.language == .english {
                // A comma can simply be punctuation after a complete date.
            } else {
                return Match(end: cursor + 1, language: lexicon.language, outcome: .incomplete, rules: ["R39"])
            }
        } else if let value = Int(word(cursor)), word(cursor + 1) != ":",
                  whitespace(between: cursor - 1, and: cursor) {
            year = value
            cursor += 1
        } else if !word(cursor).isEmpty, word(cursor).allSatisfy(\.isNumber), Int(word(cursor)) == nil,
                  whitespace(between: cursor - 1, and: cursor) {
            return Match(end: cursor + 1, language: lexicon.language, outcome: .invalid(.outOfRange), rules: ["R23"])
        }
        return Match(
            end: cursor, meaning: .calendarDate(year: year, month: month, day: day),
            language: lexicon.language, rules: ["R14", "R15", "R17"],
        )
    }
}
